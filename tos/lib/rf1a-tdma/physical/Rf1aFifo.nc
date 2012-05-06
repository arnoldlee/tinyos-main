interface Rf1aFifo{
  async command uint8_t getDecodedLen(uint8_t encodedLen);
  async command uint8_t getEncodedLen(uint8_t decodedLen);
  async command error_t readRXFIFO(uint8_t* buf, uint8_t dataBytes, 
    bool isControl);
  async command error_t writeTXFIFO(const uint8_t* buf, uint8_t dataBytes, 
    bool isControl);
  //returns true if this Rf1aFifo provider does error-checking inline
  //(thus overriding the crc bit, if it exists)
  async command bool crcOverride();
  //return crc length in encoded bytes 
  async command uint8_t getCrcLen();
}