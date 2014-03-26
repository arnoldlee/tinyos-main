from tools.cx.messages import SetSettingsStorageMsg

import tools.cx.constants

class SetTimeSync(SetSettingsStorageMsg.SetSettingsStorageMsg):
    def __init__(self, timeStamp):
        SetSettingsStorageMsg.SetSettingsStorageMsg.__init__(self)
        self.set_key(tools.cx.constants.SS_KEY_TIME_SYNC)
        self.set_len(4)
        self.setUIntElement(self.offsetBits_val(0), 32, timeStamp, 1)
