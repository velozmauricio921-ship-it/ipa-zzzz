// Simple example header for the preload .dylib POC
#ifndef PRELOAD_H
#define PRELOAD_H

#ifdef __cplusplus
extern "C"
{
#endif

    // Number of embedded files
    int preload_count(void);

    // Return the filename for index (UTF-8, caller must not free)
    const char *preload_name(int idx);

    // Allocate and return file contents for index. On success returns 0 and sets *outPtr
    // to a malloc'd buffer and *outLen to its length. Caller must call preload_free.
    int preload_get(int idx, unsigned char **outPtr, int *outLen);

    // Free buffers returned by preload_get
    void preload_free(unsigned char *ptr);

#ifdef __cplusplus
}
#endif

#endif // PRELOAD_H
