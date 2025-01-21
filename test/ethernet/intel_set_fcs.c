#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/if.h>
#include <linux/if_ether.h>
#include <linux/if_packet.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define ETH_P_ALL 0x0003 // All protocols
#define PACKET_SIZE 1500 // Maximum Ethernet frame size

// Function to calculate CRC32 for FCS
uint32_t calculate_fcs(const uint8_t *data, size_t length) {
    uint32_t crc = 0xFFFFFFFF; // Initial value
    for (size_t i = 0; i < length; i++) {
        crc ^= data[i];
        for (int j = 0; j < 8; j++) {
            if (crc & 1) {
                crc = (crc >> 1) ^ 0xEDB88320; // Polynomial
            } else {
                crc >>= 1;
            }
        }
    }
    return ~crc; // Final XOR value
}

int main() {
    int sockfd;
    struct sockaddr_ll sa;
    uint8_t packet[PACKET_SIZE];
    size_t packet_length = sizeof(struct ethhdr) + 100; // Example payload size

    // Create raw socket
    sockfd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (sockfd < 0) {
        perror("Socket creation failed");
        return EXIT_FAILURE;
    }

    // Prepare packet (Ethernet header + payload)
    struct ethhdr *eth_header = (struct ethhdr *)packet;
    memcpy(eth_header->h_source, "\x00\x11\x22\x33\x44\x55", ETH_ALEN); // Source MAC
    memcpy(eth_header->h_dest, "\x66\x77\x88\x99\xAA\xBB", ETH_ALEN);   // Destination MAC
    eth_header->h_proto = htons(ETH_P_IP); // Protocol type

    // Fill in payload with example data
    memset(packet + sizeof(struct ethhdr), 'A', 100); // Example payload

    // Calculate FCS and append it
    uint32_t fcs = calculate_fcs(packet, packet_length);
    memcpy(packet + packet_length, &fcs, sizeof(fcs));

    // Prepare sockaddr_ll structure
    memset(&sa, 0, sizeof(sa));
    sa.sll_family = AF_PACKET;
    sa.sll_protocol = htons(ETH_P_ALL);
    sa.sll_ifindex = if_nametoindex("eth0"); // Replace with your interface name

    // Send packet
    if (sendto(sockfd, packet, packet_length + sizeof(fcs), 0,
               (struct sockaddr*)&sa, sizeof(sa)) < 0) {
        perror("Packet send failed");
        close(sockfd);
        return EXIT_FAILURE;
    }

    printf("Packet sent successfully\n");

    close(sockfd);
    return EXIT_SUCCESS;
}
