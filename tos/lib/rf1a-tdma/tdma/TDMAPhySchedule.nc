interface TDMAPhySchedule{
  command error_t setSchedule(uint32_t startAt,
    uint16_t atFrameNum, uint16_t totalFrames, uint8_t symbolRate,
    uint8_t channel, bool isSynched);

  event int32_t getFrameAdjustment(uint16_t frameNum);
  async command uint32_t getNow();
  event uint8_t getScheduleNum();
  event void peek(message_t* msg, uint16_t frameNum, 
    uint32_t timestamp);
  event void resynched(uint16_t frameNum);

  //TODO: should come from transport layer AND main schedule
  event bool isInactive(uint16_t frameNum);
}
