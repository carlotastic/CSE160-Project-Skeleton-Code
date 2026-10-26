// what other modules (IP, Node) can ask the routing module
interface DistanceVector{
   // TRUE if there is a usable route to dest. Fills in nextHop and cost.
   command bool getRoute(uint16_t dest, uint16_t* nextHop, uint8_t* cost);

   // prints the routing table (routeDMP command)
   command void printTable();
}