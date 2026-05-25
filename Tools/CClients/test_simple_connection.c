#include <stdio.h>
#include <stdlib.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

int main() {
    printf("🔗 Testing connection to localhost:10000\n");
    
    // Simple socket test to see if server is running
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        printf("❌ Socket creation failed\n");
        return 1;
    }
    
    struct sockaddr_in server_addr;
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(10000);
    inet_pton(AF_INET, "127.0.0.1", &server_addr.sin_addr);
    
    int result = connect(sockfd, (struct sockaddr*)&server_addr, sizeof(server_addr));
    close(sockfd);
    
    if (result == 0) {
        printf("✅ Server is listening on port 10000\n");
        return 0;
    } else {
        printf("❌ No server found on port 10000\n");
        return 1;
    }
}
