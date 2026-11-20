interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void pingTTL(uint16_t destination, uint8_t ttl, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(uint8_t port);
   event void setTestClient(uint16_t server, uint8_t srcPort, uint8_t destPort, uint16_t transferBytes);
   event void clientClose(uint16_t server, uint8_t srcPort, uint8_t destPort);
   event void setDropRule(uint16_t src, uint8_t flags, uint16_t value, uint8_t count);
   event void pauseConsumer();
   event void resumeConsumer();
   event void setAppServer();
   event void setAppClient();
}
