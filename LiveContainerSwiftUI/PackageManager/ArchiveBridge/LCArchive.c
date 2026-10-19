#include "LCArchive.h"
#ifdef __APPLE__
#include "../../Utilities/archive.h"
#include "../../Utilities/archive_entry.h"
#else
#include <archive.h>
#include <archive_entry.h>
#endif
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <fts.h>
#include <limits.h>
struct LCArchive { struct archive *archive; const char *error; };
LCArchive *lc_archive_open(const void *bytes, size_t count) {
    LCArchive *r = calloc(1, sizeof(*r));
    if (!r) return NULL;
    r->archive = archive_read_new();
    if (!r->archive) { free(r); return NULL; }
    /* No external decompressor programs and no automatic nested extraction. */
    archive_read_support_format_tar(r->archive);
    archive_read_support_filter_none(r->archive);
    const unsigned char *magic = bytes;
    int support = ARCHIVE_OK;
    if (count >= 2 && magic[0] == 0x1f && magic[1] == 0x8b)
        support = archive_read_support_filter_gzip(r->archive);
    else if (count >= 6 && magic[0] == 0xfd && magic[1] == '7' && magic[2] == 'z')
        support = archive_read_support_filter_xz(r->archive);
    else if (count >= 4 && magic[0] == 0x28 && magic[1] == 0xb5 && magic[2] == 0x2f && magic[3] == 0xfd)
        support = archive_read_support_filter_zstd(r->archive);
    if (support != ARCHIVE_OK) {
        r->error = "Unsupported compression in this system libarchive; external decompressors are disabled";
        return r;
    }
    if (archive_read_open_memory(r->archive, bytes, count) != ARCHIVE_OK)
        r->error = "Unable to decode tar archive with available compression filters";
    return r;
}
int lc_archive_next(LCArchive *r, const char **path, int64_t *size, int *directory) {
    if (r->error) return -1;
    struct archive_entry *e = NULL;
    int status = archive_read_next_header(r->archive, &e);
    if (status == ARCHIVE_EOF) return 0;
    if (status != ARCHIVE_OK) return -1;
    int type = archive_entry_filetype(e);
    if (archive_entry_symlink(e) || archive_entry_hardlink(e) ||
        (type != AE_IFREG && type != AE_IFDIR) || archive_entry_sparse_count(e) > 0) {
        r->error = "Links, special files and sparse entries are unsupported";
        return -1;
    }
    *path = archive_entry_pathname(e);
    *size = archive_entry_size(e);
    *directory = type == AE_IFDIR;
    return 1;
}
int64_t lc_archive_read(LCArchive *r, void *buffer, size_t count) {
    return archive_read_data(r->archive, buffer, count);
}
const char *lc_archive_error(LCArchive *r) {
    const char *message = r->error ? r->error : archive_error_string(r->archive);
    return message ? message : "Malformed archive";
}
void lc_archive_close(LCArchive *r) {
    if (r) { archive_read_free(r->archive); free(r); }
}

static int ipa_error(char *out, size_t size, const char *message) {
    if (out && size) snprintf(out, size, "%s", message ? message : "IPA archive operation failed");
    return -1;
}
static int ipa_safe_path(const char *path) {
    if (!path || !*path || *path == '/' || strchr(path, '\\')) return 0;
    const char *start = path;
    for (const char *p = path;; p++) {
        if (*p == '/' || !*p) {
            size_t n = p - start;
            if ((n == 1 && start[0] == '.') || (n == 2 && start[0] == '.' && start[1] == '.')) return 0;
            if (!n && *p) return 0;
            start = p + 1;
        }
        if (!*p) break;
    }
    return 1;
}
static int ipa_parents(char *path) {
    for (char *p = path + 1; *p; p++) if (*p == '/') {
        *p = 0;
        int result = mkdir(path, 0700);
        struct stat info;
        int valid = (result == 0 || errno == EEXIST) && lstat(path, &info) == 0 && S_ISDIR(info.st_mode);
        *p = '/';
        if (!valid) return -1;
    }
    return 0;
}
int lc_ipa_extract(const char *source, const char *destination, char *error, size_t error_size) {
    struct archive *a = archive_read_new();
    archive_read_support_format_zip(a);
    archive_read_support_filter_none(a);
    if (archive_read_open_filename(a, source, 65536) != ARCHIVE_OK) {
        ipa_error(error, error_size, archive_error_string(a)); archive_read_free(a); return -1;
    }
    int result = 0, status, entries = 0;
    int64_t total = 0;
    struct archive_entry *entry;
    char path[PATH_MAX], bytes[65536];
    while ((status = archive_read_next_header(a, &entry)) == ARCHIVE_OK) {
        const char *name = archive_entry_pathname(entry);
        int kind = archive_entry_filetype(entry);
        if (++entries > 50000 || !ipa_safe_path(name) || archive_entry_symlink(entry) || archive_entry_hardlink(entry) ||
            (kind != AE_IFREG && kind != AE_IFDIR) || archive_entry_is_encrypted(entry) == 1 ||
            archive_entry_size(entry) > 1024LL * 1024 * 1024 ||
            snprintf(path, sizeof(path), "%s/%s", destination, name) >= (int)sizeof(path) || ipa_parents(path) != 0) {
            result = ipa_error(error, error_size, "Unsafe, encrypted, linked or oversized IPA entry"); break;
        }
        if (kind == AE_IFDIR) {
            size_t n = strlen(path); if (n && path[n-1] == '/') path[n-1] = 0;
            struct stat info;
            if (mkdir(path, 0700) != 0 && (lstat(path, &info) != 0 || !S_ISDIR(info.st_mode))) {
                result = ipa_error(error, error_size, "Invalid IPA directory"); break;
            }
            continue;
        }
        int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, archive_entry_perm(entry) & 0777);
        if (fd < 0) { result = ipa_error(error, error_size, "Duplicate or invalid IPA file"); break; }
        la_ssize_t count; int64_t file_size = 0;
        while ((count = archive_read_data(a, bytes, sizeof(bytes))) > 0) {
            total += count; file_size += count;
            if (total > 3LL * 1024 * 1024 * 1024 || file_size > 1024LL * 1024 * 1024) { result = -1; break; }
            la_ssize_t offset = 0;
            while (offset < count) {
                ssize_t written = write(fd, bytes + offset, count - offset);
                if (written <= 0) { result = -1; break; }
                offset += written;
            }
            if (result) break;
        }
        close(fd);
        if (count < 0 || result) { result = ipa_error(error, error_size, "IPA decode or storage limit failure"); break; }
    }
    if (!result && status != ARCHIVE_EOF) result = ipa_error(error, error_size, archive_error_string(a));
    archive_read_free(a);
    return result;
}
int lc_ipa_pack(const char *source, const char *destination, char *error, size_t error_size) {
    struct archive *a = archive_write_new();
    archive_write_set_format_zip(a);
    if (archive_write_open_filename(a, destination) != ARCHIVE_OK) {
        ipa_error(error, error_size, archive_error_string(a)); archive_write_free(a); return -1;
    }
    char *paths[] = { (char *)source, NULL };
    FTS *tree = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR, NULL);
    int result = tree ? 0 : -1;
    FTSENT *item;
    char bytes[65536];
    while (tree && (item = fts_read(tree))) {
        if (item->fts_level == 0 || item->fts_info == FTS_DP) continue;
        if (item->fts_info != FTS_D && item->fts_info != FTS_F) { result = -1; break; }
        struct archive_entry *entry = archive_entry_new();
        archive_entry_set_pathname(entry, item->fts_path + strlen(source) + 1);
        archive_entry_copy_stat(entry, item->fts_statp);
        if (archive_write_header(a, entry) != ARCHIVE_OK) result = -1;
        archive_entry_free(entry);
        if (result) break;
        if (item->fts_info == FTS_F) {
            int fd = open(item->fts_accpath, O_RDONLY | O_NOFOLLOW);
            if (fd < 0) { result = -1; break; }
            ssize_t count;
            while ((count = read(fd, bytes, sizeof(bytes))) > 0) {
                if (archive_write_data(a, bytes, count) != count) { result = -1; break; }
            }
            close(fd);
            if (count < 0 || result) { result = -1; break; }
        }
    }
    if (tree) fts_close(tree);
    if (archive_write_close(a) != ARCHIVE_OK) result = -1;
    if (result) ipa_error(error, error_size, "Unable to package IPA; unsupported file or insufficient storage");
    archive_write_free(a);
    return result;
}
