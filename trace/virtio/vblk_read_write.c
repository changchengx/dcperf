/* SPDX-License-Identifier: Apache-2.0
 * Copyright(c) 2025 Liu, Changcheng <changcheng.liu@aliyun.com>
 */

// gcc vblk_read_write.c -o vblk_read_write

#define _GNU_SOURCE
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

int main(int argc, char* argv[]) {
    const char *device = NULL;
    if (argc == 1) {
        perror("vblk_read_write [/dev/vdX] [read or write]");
	return 1;
    }

    device = argv[1];

    int IO_OUT_WRITE = 1;
    if (argc > 2 && strcmp(argv[2], "read") == 0) {
	IO_OUT_WRITE = 0;
    }

    int oflag = O_DIRECT | O_SYNC;
    oflag |= IO_OUT_WRITE ? O_WRONLY : O_RDONLY;

    int fd = open(device, oflag);
    if (fd == -1) {
        perror("Error opening device");
        return 1;
    }

    // Allocate a buffer aligned to the block size (512 bytes)
    void *buffer;
    if (posix_memalign(&buffer, 512, 512) != 0) {
        perror("Error allocating aligned memory");
        close(fd);
        return 1;
    }
    memset(buffer, 0, 512);  // Fill the buffer with zeros

    ssize_t ret = IO_OUT_WRITE ? write(fd, buffer, 512) : read(fd, buffer, 512);
    if (ret == -1) {
        fprintf(stderr, "Error %s device:%s", IO_OUT_WRITE ? "write" : "read", device);
    } else {
        printf("%s %zd bytes to device\n", IO_OUT_WRITE ? "write" : "read", ret);
    }

    while(1);

#if 0
    free(buffer);
    close(fd);
#endif

    return 0;
}
