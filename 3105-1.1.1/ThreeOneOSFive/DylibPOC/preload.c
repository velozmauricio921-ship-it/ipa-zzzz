#include "preload.h"
#include <stdlib.h>
#include <string.h>

// Example: embed one tiny .3105 blob. Replace with real encrypted bytes when building.
static const unsigned char file0_data[] = {0x50, 0x4F, 0x43, 0x00};
static const int file0_len = (int)sizeof(file0_data);
static const char *file0_name = "Free Fire/Visuals/EXAMPLE.3105";

int preload_count(void)
{
    return 1;
}

const char *preload_name(int idx)
{
    if (idx == 0)
        return file0_name;
    return NULL;
}

int preload_get(int idx, unsigned char **outPtr, int *outLen)
{
    if (idx == 0)
    {
        unsigned char *buf = (unsigned char *)malloc(file0_len);
        if (!buf)
            return -1;
        memcpy(buf, file0_data, file0_len);
        *outPtr = buf;
        *outLen = file0_len;
        return 0;
    }
    return -1;
}

void preload_free(unsigned char *ptr)
{
    if (ptr)
        free(ptr);
}
