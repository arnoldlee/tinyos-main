#include "decodeError.h"
#include "baconCollect.h"
#include "I2CCom.h"
#include "Msp430Adc12.h"
#include "I2CADCReader.h"



module LeafP{
  uses interface Boot;
  uses interface Leds;
  uses interface Random;
  uses interface Crc;

  
  /* bacon sensors */
#ifdef USE_BACON_ADC  
  uses interface SplitControl as BatteryControl;
  uses interface Read<uint16_t> as BatteryVoltage;

  uses interface SplitControl as LightControl;
  uses interface Read<uint16_t> as Apds9007;

  uses interface SplitControl as TempControl;
  uses interface Read<uint16_t> as Mcp9700;

  uses interface Timer<TMilli> as BaconSampleTimer;
#endif

  /* toast board */
#ifdef USE_TOAST_ADC  
  uses interface I2CDiscoverer;
  uses interface I2CADCReaderMaster;

  uses interface Timer<TMilli> as ToastSampleTimer;
#endif

  /* Timers */  
  uses interface Timer<TMilli> as StatusSampleTimer;
  uses interface Timer<TMilli> as OffloadTimer;
  uses interface Timer<TMilli> as DelayTimer;
  uses interface Timer<TMilli> as WDTResetTimer;
  uses interface Timer<TMilli> as LedsTimer;

  /* Radio */
  uses interface SplitControl as RadioControl;
  uses interface AMSend as PeriodicSend;
  uses interface AMSend as ControlSend;
  uses interface Receive as ControlReceive;
  uses interface Packet;
  uses interface AMPacket;
  uses interface Rf1aPacket;
//  uses interface PacketAcknowledgements;
//  uses interface SplitControl as PhysicalControl;
  uses interface Pool<message_t> as SendPool;
  uses interface Queue<message_t*> as SendQueue;

  /* flash */
  uses interface LogRead;
  uses interface LogWrite;
  uses interface Pool<sample_t> as WritePool;
  uses interface Queue<sample_t*> as WriteQueue;

  uses interface HplMsp430GeneralIO as CS;
  uses interface HplMsp430GeneralIO as FlashEnable;
  uses interface HplMsp430GeneralIO as ToastEnable;

#ifdef DEBUG
  /* UART */
  uses interface StdControl as SerialControl;
  uses interface UartStream;
#endif

  
} implementation {


  /*************************/
  /* toast                 */  
  /*************************/
#ifdef USE_TOAST_ADC  
  
  typedef struct {
    uint8_t address;
    uint32_t id_high;
    uint32_t id_low;
  } toast_address_t;

  toast_address_t toastAddress[2]; // mapping between local address and unique address

  uint8_t toastCounter; // number of discoverd toasts  
  uint8_t currentToast; // the toast board currently being sampled

  i2c_message_t i2cMessage;
  i2c_message_t* i2cMessagePtr = &i2cMessage; 

  task void initChannelsTask(); // configure i2c packet read settings
  task void toastDiscoveryTask(); 

#endif

  /*************************/
  /* flash                 */
  /*************************/

  task void logReadWriteTask();
  bool flashIsNotBusy = TRUE;


  uint32_t offloadCookie; // read cookie
  uint8_t offloadBuffer[FLASH_MAX_READ]; // read buffer
  bool fillSendPool = FALSE;
  task void flashToSendPoolTask();

  uint8_t checkMessage(uint8_t* pl, bool doCrc); // check record consistency

  /*************************/
  /* leds                  */
  /*************************/
  uint8_t blinkTaskParameter; // led bit map
  task void blinkTask();

  /*************************/
  /* time sync             */
  /*************************/
  uint16_t remoteSource; // remote node id
  uint8_t remoteBoot; // remote boot counter
  uint32_t remoteTime; // remote clock counter
  uint8_t remoteRtc[7]; // remote real-time clock 
  task void clockSampleTask();
  

  /*************************/
  /* sampling              */
  /*************************/

#ifdef USE_BACON_ADC  
  sample_bacon_t * baconSamplePointer;
  task void baconSampleTask();
  uint32_t bacon_sample_interval = BACON_SAMPLE_INTERVAL;
#endif

#ifdef USE_TOAST_ADC  
  sample_toast_t * toastSamplePointer;
  uint32_t toast_sample_interval = TOAST_SAMPLE_INTERVAL;
  task void toastSampleTask();
#endif

  uint32_t status_sample_interval = STATUS_SAMPLE_INTERVAL;
  task void statusSampleTask();

  uint32_t offload_sample_interval = OFFLOAD_SAMPLE_INTERVAL;

  // status samples       
  uint32_t radioOnTime;
  uint32_t radioOffTime;
  uint32_t lastTime;

  /*************************/
  /* radio                 */
  /*************************/

  uint16_t gateway = DEFAULT_GATEWAY;

  // periodic channel
  bool sendIsNotBusy = TRUE;
  task void sendTask();
  task void delaySendTask();

  // control channel
  message_t controlMessage;  
  uint8_t controlTaskParameter;
  task void controlTask();



  /*************************/
  uint8_t __attribute__ ((section(".noinit"))) boot_counter; // local boot counter

  /***************************************************************************/

  event void Boot.booted()
  {
    // power on 1-wire bus - should be moved to driver
    call ToastEnable.set();
    call ToastEnable.makeOutput();
    call ToastEnable.selectIOFunc();

    // power on external flash - should be moved to driver
    call FlashEnable.set();
    call FlashEnable.makeOutput();
    call FlashEnable.selectIOFunc();

#ifdef DEBUG    
    call SerialControl.start();
#endif

    // set WDT to reset at 1 second; set timer to renew every half second
    call WDTResetTimer.startPeriodic(512);
    WDTCTL = WDT_ARST_1000;


    // keep radio on; rely on radio stack to duty-cycle radio
    call RadioControl.start();
  }


  /***************************************************************************/
  /* Flash                                                                   */
  /***************************************************************************/

  event void LogWrite.syncDone(error_t error) 
  { 
    // use reset vector to determine if boot counter should be reset (bsl)
    // or incremented (WDT, etc)
    uint16_t reset_vector = SYSRSTIV;
    if (reset_vector == 0x04)
      boot_counter = 0;
    else
      ++boot_counter;

#ifdef DEBUG
    printf("leaf: %d %X\n\r",boot_counter, reset_vector);
    printf("r/w: %lu %lu\n\r", call LogRead.currentOffset(), call LogWrite.currentOffset() );
#endif

    // point offload cookie to current write pointer 
    // and let basestation rewind if necessary       
    offloadCookie = call LogWrite.currentOffset();

#ifdef USE_TOAST_ADC  
    // initialize I2C sample packet
    post initChannelsTask();

    // discover toast boards
    post toastDiscoveryTask();
#endif

    // start periodic sample timers
#ifdef USE_BACON_ADC  
    call BaconSampleTimer.startPeriodic(bacon_sample_interval);
#endif
#ifdef USE_TOAST_ADC  
    call ToastSampleTimer.startPeriodic(toast_sample_interval);
#endif

    call StatusSampleTimer.startPeriodic(status_sample_interval);

    // start periodic offload timer
    call OffloadTimer.startPeriodic(offload_sample_interval);

    // flash leds to signal successful boot 
    blinkTaskParameter = LEDS_LED0|LEDS_LED1|LEDS_LED2;
    post blinkTask();
  }

// main program files
// periodically sample (virtual) sensors and store results in flash
#include "SamplesToFlash.nc"

// periodically offload measurements from flash over the radio
#include "FlashToRadio.nc"


  /***************************************************************************/
  /* Misc.                                                                   */
  /***************************************************************************/

  event void WDTResetTimer.fired() 
  {
    //re-up the wdt
    WDTCTL =  WDT_ARST_1000;
  }


  // set the leds according to the blinkTaskParameter bit pattern
  // and use the LedsTimer to make a dimming effect
  task void blinkTask()
  {
    call Leds.set(blinkTaskParameter);
    call LedsTimer.startOneShot(512);
  }

  event void LedsTimer.fired() 
  {
    if (blinkTaskParameter & LEDS_LED2)
    {
      blinkTaskParameter &= ~LEDS_LED2;
      call Leds.led2Off();
      call LedsTimer.startOneShot(256);
    }
    else if (blinkTaskParameter & LEDS_LED1)
    {
      blinkTaskParameter &= ~LEDS_LED1;
      call Leds.led1Off();
      call LedsTimer.startOneShot(256);
    }
    else 
    {
      blinkTaskParameter = 0;
      call Leds.led0Off();
    }  
  }


  /***************************************************************************/
  /* UART                                                                    */
  /***************************************************************************/
#ifdef DEBUG
  norace uint8_t uartByte;
  task void uartTask();

  async event void UartStream.receivedByte(uint8_t byte) {

    uartByte = byte;
    
    post uartTask();
  }
  
  task void uartTask()
  {
  
    switch ( uartByte ) {
   
      case '1':
        call RadioControl.stop();
        break;
      case '2':
        call RadioControl.start();
        break;
   
      case '3':
        printf("1wb off\n\r");
        call ToastEnable.clr();
        break;

      case '4':
        printf("1wb on\n\r");
        call ToastEnable.set();
        break;

      case 'd':
        call LogRead.seek(SEEK_BEGINNING);
        break;

      case 'r':
        call LogRead.read(offloadBuffer, FLASH_MAX_READ);
        break;

      case 'w':
        call LogWrite.sync();
        break;

      case 'e':
        call LogWrite.erase();
        break;

#ifdef USE_TOAST_ADC
      case 't':
        post toastDiscoveryTask();
        break;
#endif

      case 's':
        break;
        
      case 'q':
        WDTCTL = 0;
        break;

      case '\r':
        printf("\n\r");
        break;

      default:
        printf("%c", uartByte);
        break;
    }
  }
  
  async event void UartStream.receiveDone( uint8_t* buf_, uint16_t len,
    error_t error ){}
  async event void UartStream.sendDone( uint8_t* buf_, uint16_t len,
    error_t error ){}

#endif
}


