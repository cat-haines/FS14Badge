const WAKE_INTERVAL = 900;      // wake every 15 minutes
const DEBUG = 1;                // log

const LED_ON = 0;
const LED_OFF = 1;

function log(string) {
    if (DEBUG == 1) server.log(string);
}

/****************************** GPIO Expander ******************************/

class SX150x{
    //Private variables
    _i2c       = null;
    _addr      = null;
    _callbacks = null;
 
    //Pass in pre-configured I2C since it may be used by other devices
    constructor(i2c, address = 0x40) {
        _i2c  = i2c;
        _addr = address;  //8-bit address
        _callbacks = [];
    }
 
    function readReg(register) {
        local data = _i2c.read(_addr, format("%c", register), 1);
        if (data == null) {
            server.error("I2C Read Failure. Device: "+_addr+" Register: "+register);
            return -1;
        }
        return data[0];
    }
    
    function writeReg(register, data) {
        _i2c.write(_addr, format("%c%c", register, data));
    }
    
    function writeBit(register, bitn, level) {
        local value = readReg(register);
        value = (level == 0)?(value & ~(1<<bitn)):(value | (1<<bitn));
        writeReg(register, value);
    }
    
    function writeMasked(register, data, mask) {
        local value = readReg(register);
        value = (value & ~mask) | (data & mask);
        writeReg(register, value);
    }
 
    // set or clear a selected GPIO pin, 0-16
    function setPin(gpio, level) {
        writeBit(bank(gpio).REGDATA, gpio % 8, level ? 1 : 0);
    }
 
    // configure specified GPIO pin as input(0) or output(1)
    function setDir(gpio, output) {
        writeBit(bank(gpio).REGDIR, gpio % 8, output ? 0 : 1);
    }
 
    // enable or disable internal pull up resistor for specified GPIO
    function setPullUp(gpio, enable) {
        writeBit(bank(gpio).REGPULLUP, gpio % 8, enable ? 0 : 1);
    }
    
    // enable or disable internal pull down resistor for specified GPIO
    function setPullDown(gpio, enable) {
        writeBit(bank(gpio).REGPULLDN, gpio % 8, enable ? 0 : 1);
    }
 
    // configure whether specified GPIO will trigger an interrupt
    function setIrqMask(gpio, enable) {
        writeBit(bank(gpio).REGINTMASK, gpio % 8, enable ? 0 : 1);
    }
 
    // clear interrupt on specified GPIO
    function clearIrq(gpio) {
        writeBit(bank(gpio).REGINTMASK, gpio % 8, 1);
    }
 
    // get state of specified GPIO
    function getPin(gpio) {
        return ((readReg(bank(gpio).REGDATA) & (1<<(gpio%8))) ? 1 : 0);
    }
 
    //configure which callback should be called for each pin transition
    function setCallback(gpio, callback){
        _callbacks.insert(gpio,callback);
    }
 
    function callback(){
        //server.log("Checking for callback...");
        local irq = getIrq();
        //server.log(format("IRQ = %08x",irq));
        clearAllIrqs();
        for (local i = 0; i < 16; i++){
            if ( (irq & (1 << i)) && (typeof _callbacks[i] == "function")){
                _callbacks[i]();
            }
        }
    }
}

class SX1506 extends SX150x{
    // I/O Expander internal registers
    static BANK_A = {   REGDATA    = 0x01,
                        REGDIR     = 0x03,
                        REGPULLUP  = 0x05,
                        REGPULLDN  = 0x07,
                        REGINTMASK = 0x09,
                        REGSNSHI   = 0x0B,
                        REGSNSLO   = 0x0D,
                        REGINTSRC  = 0x0F}
 
    static BANK_B = {   REGDATA    = 0x00,
                        REGDIR     = 0x02,
                        REGPULLUP  = 0x04,
                        REGPULLDN  = 0x06,
                        REGINTMASK = 0x08,
                        REGSNSHI   = 0x0A,
                        REGSNSLO   = 0x0C,
                        REGINTSRC  = 0x0E}
 
    constructor(i2c, address=0x40){
        base.constructor(i2c, address);
        _callbacks.resize(16,null);
        this.reset();
        this.clearAllIrqs();
    }
    
    //Write registers to default values
    function reset(){
        writeReg(BANK_A.REGDIR, 0xFF);
        writeReg(BANK_A.REGDATA, 0xFF);
        writeReg(BANK_A.REGPULLUP, 0x00);
        writeReg(BANK_A.REGPULLDN, 0x00);
        writeReg(BANK_A.REGINTMASK, 0xFF);
        writeReg(BANK_A.REGSNSHI, 0x00);
        writeReg(BANK_A.REGSNSLO, 0x00);
        
        writeReg(BANK_B.REGDIR, 0xFF);
        writeReg(BANK_B.REGDATA, 0xFF);
        writeReg(BANK_B.REGPULLUP, 0x00);
        writeReg(BANK_B.REGPULLDN, 0x00);
        writeReg(BANK_A.REGINTMASK, 0xFF);
        writeReg(BANK_B.REGSNSHI, 0x00);
        writeReg(BANK_B.REGSNSLO, 0x00);
    }
 
    function debug(){
        server.log(format("A-DATA   (0x%02X): 0x%02X",BANK_A.REGDATA, readReg(BANK_A.REGDATA)));
        imp.sleep(0.1);
        server.log(format("A-DIR    (0x%02X): 0x%02X",BANK_A.REGDIR, readReg(BANK_A.REGDIR)));
        imp.sleep(0.1);
        server.log(format("A-PULLUP (0x%02X): 0x%02X",BANK_A.REGPULLUP, readReg(BANK_A.REGPULLUP)));
        imp.sleep(0.1);
        server.log(format("A-PULLDN (0x%02X): 0x%02X",BANK_A.REGPULLDN, readReg(BANK_A.REGPULLDN)));
        imp.sleep(0.1);
        server.log(format("A-INTMASK (0x%02X): 0x%02X",BANK_A.REGINTMASK, readReg(BANK_A.REGINTMASK)));
        imp.sleep(0.1);
        server.log(format("A-SNSHI  (0x%02X): 0x%02X",BANK_A.REGSNSHI, readReg(BANK_A.REGSNSHI)));
        imp.sleep(0.1);
        server.log(format("A-SNSLO  (0x%02X): 0x%02X",BANK_A.REGSNSLO, readReg(BANK_A.REGSNSLO)));
        imp.sleep(0.1);
        server.log(format("B-DATA   (0x%02X): 0x%02X",BANK_B.REGDATA, readReg(BANK_B.REGDATA)));
        imp.sleep(0.1);
        server.log(format("B-DIR    (0x%02X): 0x%02X",BANK_B.REGDIR, readReg(BANK_B.REGDIR)));
        imp.sleep(0.1);
        server.log(format("B-PULLUP (0x%02X): 0x%02X",BANK_B.REGPULLUP, readReg(BANK_B.REGPULLUP)));
        imp.sleep(0.1);
        server.log(format("B-PULLDN (0x%02X): 0x%02X",BANK_B.REGPULLDN, readReg(BANK_B.REGPULLDN)));
        imp.sleep(0.1);
        server.log(format("B-INTMASK (0x%02X): 0x%02X",BANK_B.REGINTMASK, readReg(BANK_B.REGINTMASK)));
        imp.sleep(0.1);
        server.log(format("B-SNSHI  (0x%02X): 0x%02X",BANK_B.REGSNSHI, readReg(BANK_B.REGSNSHI)));
        imp.sleep(0.1);
        server.log(format("B-SNSLO  (0x%02X): 0x%02X",BANK_B.REGSNSLO, readReg(BANK_B.REGSNSLO)));
        
        // imp.sleep(0.1);
        // foreach(idx,val in BANK_A){
        //     server.log(format("Bank A %s (0x%02X): 0x%02X", idx, val, readReg(val)));
        //     imp.sleep(0.1);
        // }
        // foreach(idx,val in BANK_B){
        //     server.log(format("Bank B %s (0x%02X): 0x%02X", idx, val, readReg(val)));
        //     imp.sleep(0.1);
        // }
        // for(local i =0; i < 0x2F; i++){
        //     server.log(format("0x%02X: 0x%02X", i, readReg(i)));
        // }
 
    }
 
    function bank(gpio){
        return (gpio > 7) ? BANK_B : BANK_A;
    }
 
    // configure whether edges trigger an interrupt for specified GPIO
    function setIrqEdges( gpio, rising, falling) {
        local bank = bank(gpio);
        gpio = gpio % 8;
        local mask = 0x03 << ((gpio & 3) << 1);
        local data = (2*falling + rising) << ((gpio & 3) << 1);
        writeMasked(gpio >= 4 ? bank.REGSNSHI : bank.REGSNSLO, data, mask);
    }
 
    function clearAllIrqs() {
        writeReg(BANK_A.REGINTSRC,0xff);
        writeReg(BANK_B.REGINTSRC,0xff);
    }
 
    function getIrq(){
        return ((readReg(BANK_B.REGINTSRC) & 0xFF) << 8) | (readReg(BANK_A.REGINTSRC) & 0xFF);
    }
}

class ExpGPIO{
    _expander = null;  //Instance of an Expander class
    _gpio     = null;  //Pin number of this GPIO pin
    
    constructor(expander, gpio) {
        _expander = expander;
        _gpio     = gpio;
    }
    
    //Optional initial state (defaults to 0 just like the imp)
    function configure(mode, callback = null, initialstate=0) {
        // set the pin direction and configure the internal pullup resistor, if applicable
        _expander.setPin(_gpio,initialstate);
        if (mode == DIGITAL_OUT) {
            _expander.setDir(_gpio,1);
            _expander.setPullUp(_gpio,0);
        } else if (mode == DIGITAL_IN) {
            _expander.setDir(_gpio,0);
            _expander.setPullUp(_gpio,0);
        } else if (mode == DIGITAL_IN_PULLUP) {
            _expander.setDir(_gpio,0);
            _expander.setPullUp(_gpio,1);
        }
        
        // configure the pin to throw an interrupt, if necessary
        if (callback) {
            _expander.setIrqMask(_gpio,1);
            _expander.setIrqEdges(_gpio,1,1);
            _expander.setCallback(_gpio,callback);            
        } else {
            _expander.setIrqMask(_gpio,0);
            _expander.setIrqEdges(_gpio,0,0);
            _expander.setCallback(_gpio,null);
        }
    }
    
    function write(state) { _expander.setPin(_gpio,state); }
    
    function read() { return _expander.getPin(_gpio); }
}

/******************************** Thermistor *******************************/

class Thermistor {
        // thermistor constants are shown on your thermistor datasheet
        // beta value (for the temp range your device will operate in)
        b_therm                 = null;
        t0_therm                = null;
        // nominal resistance of the thermistor at room temperature
        r0_therm                = null;

        // analog input pin
        p_therm                 = null;
        points_per_read         = null;

        high_side_therm         = null;

        constructor(pin, b, t0, r, points = 10, _high_side_therm = true) {
                this.p_therm = pin;
                this.p_therm.configure(ANALOG_IN);

                // force all of these values to floats in case they come in as integers
                this.b_therm = b * 1.0;
                this.t0_therm = t0 * 1.0;
                this.r0_therm = r * 1.0;
                this.points_per_read = points * 1.0;

                this.high_side_therm = _high_side_therm;
        }

        // read thermistor in Kelvin
        function read() {
                local vdda_raw = 0;
                local vtherm_raw = 0;
                for (local i = 0; i < points_per_read; i++) {
                        vdda_raw += hardware.voltage();
                        vtherm_raw += p_therm.read();
                }
                local vdda = (vdda_raw / points_per_read);
                local v_therm = (vtherm_raw / points_per_read) * (vdda / 65535.0);
                local r_therm = 0;        
                if (high_side_therm) {
                        r_therm = (vdda - v_therm) * (r0_therm / v_therm);
                } else {
                        r_therm = r0_therm / ((vdda / v_therm) - 1);
                }

                local ln_therm = math.log(r0_therm / r_therm);
                local t_therm = (t0_therm * b_therm) / (b_therm - t0_therm * ln_therm);
                return t_therm;
        }

        // read thermistor in Celsius
        function read_c() {
                return this.read() - 273.15;
        }

        // read thermistor in Fahrenheit
        function read_f() {
                local temp = this.read() - 273.15;
                return (temp * 9.0 / 5.0 + 32.0);
        }
}

/****************************** Battery Sensor *****************************/

class Battery {
    vbat_sns_en = null;
    vbat_sns    = null;
    chg_status  = null;
    
    constructor(_vbat_sns_en, _vbat_sns, _chg_status) {
        vbat_sns_en = _vbat_sns_en;
        vbat_sns    = _vbat_sns;
        chg_status  = _chg_status;
    }
    
    function read_voltage() {
        vbat_sns_en.write(1);
        local vbat = (vbat_sns.read()/65535.0) * hardware.voltage() * (6.9/4.7);
        vbat_sns_en.write(0);
        
        return vbat;
    }
    
    function charge_status() {
        if (chg_status.read()) {
            return false;
        } else {
            return true;
        }
    }
}

/********************* Instantiate Some of the Things!! ********************/
i2c         <- hardware.i2c89;
ioexp_int   <- hardware.pin1;   // I/O Expander Alert

// Bus configs
i2c.configure(CLOCK_SPEED_100_KHZ);

// Initialize the 16-channel I2C I/O Expander (SX1505)
ioexp <- SX1506(i2c, 0x40);    // instantiate I/O Expander

// Make GPIO instances for each IO on the expander
btn1 <- ExpGPIO(ioexp, 4);     // User Button 1 (GPIO 4)
btn2 <- ExpGPIO(ioexp, 5);     // User Button 2 (GPIO 5)
led  <- ExpGPIO(ioexp, 10);

// Initialize the interrupt Pin
ioexp_int.configure(DIGITAL_IN_WAKEUP, ioexp.callback.bindenv(ioexp));

vbat_sns        <- hardware.pinA;   // Battery Voltage Sense (ADC)
vbat_sns.configure(ANALOG_IN);
temp_sns        <- hardware.pinB;   // Temperature Sense (ADC)

// Battery Charge Status on GPIO Expander
chg_status      <- ExpGPIO(ioexp, 6)

chg_status.configure(DIGITAL_IN);

// VBAT_SNS_EN on GPIO Expander
vbat_sns_en     <- ExpGPIO(ioexp, 7);
vbat_sns_en.configure(DIGITAL_OUT, 0);    // VBAT_SNS_EN (GPIO Expander Pin7)

// Initialize the thermistor
therm           <- Thermistor(temp_sns, 3340, 298, 10000);

// Initialize the battery
battery         <- Battery(vbat_sns_en, vbat_sns, chg_status);

// Configure the LED
led.configure(DIGITAL_OUT);
led.write(0);

// Create Pin objects for broken out GPIO pins
pin11 <- ExpGPIO(ioexp, 11);
pin12 <- ExpGPIO(ioexp, 12);
pin13 <- ExpGPIO(ioexp, 13);
pin14 <- ExpGPIO(ioexp, 14);
pin15 <- ExpGPIO(ioexp, 15);

/***************************** Application Code ****************************/
// turn led on
led.write(LED_ON);

function readAndSend() {
    // read and send
    local timestamp = time();
    local temp = therm.read_c();
    local battery = battery.read_voltage();

    agent.send("data", { t = temp, b = battery, ts = timestamp })
}

readAndSend();
imp.onidle(function() { 
    led.write(LED_OFF);
    imp.deepsleepfor(WAKE_INTERVAL); 
});


