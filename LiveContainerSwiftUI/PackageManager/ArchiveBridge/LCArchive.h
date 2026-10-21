#ifndef LC_ARCHIVE_H
#define LC_ARCHIVE_H
#include <stddef.h>
#include <stdint.h>
typedef struct LCArchive LCArchive;
LCArchive *lc_archive_open(const void *bytes, size_t count);
/* 1 = entry, 0 = EOF, -1 = error. Input memory must outlive the reader. */
int lc_archive_next(LCArchive *reader, const char **path, int64_t *size, int *directory);
int64_t lc_archive_read(LCArchive *reader, void *buffer, size_t count);
const char *lc_archive_error(LCArchive *reader);
void lc_archive_close(LCArchive *reader);
/* Decode a raw gzip/xz/bzip2 Packages index into a caller-bounded buffer. */
int64_t lc_index_expand(const void *bytes, size_t count, void *output, size_t capacity);
/* Streaming IPA operations. Only regular files/directories; bounded expansion, no links. */
int lc_ipa_extract(const char *source, const char *destination, char *error, size_t error_size);
int lc_ipa_pack(const char *source, const char *destination, char *error, size_t error_size);
#endif
