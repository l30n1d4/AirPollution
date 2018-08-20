----------------------------------------------------------------------------------
------------------  air pollution (nodeMCU + PMS5003 + bme280)  ------------------
----------------------------------------------------------------------------------

-- REVISION: 1.1.0 (07/08/2018)
-- addedd: idStation

-- REVISION: 1.0.1 (28/04/2018)
-- addedd: cron schedulation

-- TODO: gestione ora legale/solare + sensore GPS + RTC (dal GPS no da internet)

-- modules: adc,bit,bme280,cron,crypto,dht,encoder,enduser_setup,file,gpio,http,i2c,net,node,pwm,rtctime,sjson,sntp,spi,tmr,u8g,uart,websocket,wifi


----------------------------------------------------------------------------------
-- variabili globali
stazione = 'roma' -- position of the measurement place
idStation = 1 -- id of station: the position may be change but the id no
----------------------------------------------------------------------------------
ssid = "--------"
pass = "........"
url = 'http://xxxxxxx.yyyyyyy.it/insert.php' -- URL of insert DB service

if stazione == 'roma' then position = 'xx.yyyyyy,xx.yyyyyy' alt = 155 --altitude in meter
elseif stazione == 'milano' then position = 'xx.yyyyyy,xx.yyyyyy' alt = 112 --altitude in meter
else position = 'test' alt = 0 end

----------------------------------------------------------------------------------
-- funzione di conversione del treno di dati in arrivo dal sensore di inquinamento
function parse(data)
    local bs = {}
    for i = 1, #data do
        bs[i] = string.byte(data, i)
    end
    if (bs[1] ~= 0x42) or (bs[2] ~= 0x4d) then
        return nil
    end
    listenPM(false) -- stop to listen sensor
    local d = {}
    d['pm1_0ST'] = bs[5] * 256 + bs[6]
    d['pm2_5ST'] = bs[7] * 256 + bs[8]
    d['pm_10ST'] = bs[9] * 256 + bs[10]
    d['pm1_0AT'] = bs[11] * 256 + bs[12]
    d['pm2_5AT'] = bs[13] * 256 + bs[14]
    d['pm_10AT'] = bs[15] * 256 + bs[16]
    d['count0_3um'] = bs[17] * 256 + bs[18]
    d['count0_5um'] = bs[19] * 256 + bs[20]
    d['count1_0um'] = bs[21] * 256 + bs[22]
    d['count2_5um'] = bs[23] * 256 + bs[24]
    d['count5_0um'] = bs[25] * 256 + bs[26]
    d['count10_um'] = bs[27] * 256 + bs[28]
    return d
end -- parse

----------------------------------------------------------------------------------
-- funzione di inizializzazione del WIFI
function initWIFI(s, p)
    print("Setting up WIFI...")
    print("Waiting for AP '"..s.."'...")
    wifi.setmode(wifi.STATION)
    wifi.setphymode(wifi.PHYMODE_B) -- low power 50mA

    local cfg = {}
    cfg.ssid = s
    cfg.pwd = p
    wifi.sta.config(cfg)

    wifi.sta.connect()
    tmr.alarm(1, 2000, 1,
        function()
            if wifi.sta.getip()== nil then
                print("IP unavailable, Waiting...")
            else
                tmr.stop(1)
                print("Config done, IP is: "..wifi.sta.getip())
                syncRtcTime()
            end
        end -- function
    )
end -- initWIFI

----------------------------------------------------------------------------------
-- funzione di inizializzazione della velocita' della porta UART (seriale)
function initUART(v)
    if v == nil then
       v = 9600
    end
    uart.setup(0, v, 8, 0, 1, 0)
end -- initUART

----------------------------------------------------------------------------------
-- funzione di sincronizzazione del Time di sistema
function syncRtcTime()
    print("Setting up TIME...")
    sntp.sync({ '1.pool.ntp.org', '2.pool.ntp.org', '3.pool.ntp.org' },
        function(sec, usec, server, info)
            rtctime.set(sec + 3600, usec) -- offset 3600seconds from UTC time
            print('Sync done, epoch time is: '..sec)
            schedula()
        end, -- function
        function()
            print('Failed sync sntp!')
            print('### REBOOT ###')
            tmr.delay(5000000) -- 5seconds
            node.restart()
        end -- function
    )
end -- syncRtcTime


----------------------------------------------------------------------------------
-- funzione di schedulazione dei job/listener
function schedula()
    cron.schedule("*/5 * * * *", function(e)
        listenPM(true) -- start to listen sensor
    end)
    print('Scheduled sampler every 5 minutes')
    cron.schedule("2 */6 * * *", function(e)
        node.restart() -- reboot nodemcu
    end)
    print('Scheduled node.restart() every 6 hours')
end -- schedula

----------------------------------------------------------------------------------
-- funzione di put dei valori verso il servizio web
function putValue(vals)
    http.post(url, 'Content-Type: application/json\r\n', vals,
        function(code, data)
            if (code < 0) then
                print("HTTP request failed")
            else
                print("HTTP "..code.." - RESP: "..data)
            end
        end) -- function
end -- putValue

----------------------------------------------------------------------------------
-- funzione di creazione del JSON
function buildJSON(d)
    sT, sQFE, sQNH, sPressure, sHumidity, sDew_point = readBME()
    if sT == nil then sT = 'null' end
    if sQFE == nil then sQFE = 'null' end
    if sQNH == nil then sQNH = 'null' end
    if sPressure == nil then sPressure = 'null' end
    if sHumidity == nil then sHumidity = 'null' end
    if sDew_point == nil then sDew_point = 'null' end

    local tm = rtctime.epoch2cal(rtctime.get())
    local sTime = string.format("%04d-%02d-%02d %02d:%02d:%02d", tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"])

    local sJ = '{"TS":"'..sTime..'",'
    sJ = sJ..'"POS":"'..position..'",'
    sJ = sJ..'"ID":"'..idStation..'",'
    sJ = sJ..'"ALT":"'..alt..'",'
    sJ = sJ..'"PM":{'
    sJ = sJ..'"pm1_0ST":"'..d['pm1_0ST']..'",'
    sJ = sJ..'"pm2_5ST":"'..d['pm2_5ST']..'",'
    sJ = sJ..'"pm_10ST":"'..d['pm_10ST']..'",'
    sJ = sJ..'"pm1_0AT":"'..d['pm1_0AT']..'",'
    sJ = sJ..'"pm2_5AT":"'..d['pm2_5AT']..'",'
    sJ = sJ..'"pm_10AT":"'..d['pm_10AT']..'",'
    sJ = sJ..'"count0_3um":"'..d['count0_3um']..'",'
    sJ = sJ..'"count0_5um":"'..d['count0_5um']..'",'
    sJ = sJ..'"count1_0um":"'..d['count1_0um']..'",'
    sJ = sJ..'"count2_5um":"'..d['count2_5um']..'",'
    sJ = sJ..'"count5_0um":"'..d['count5_0um']..'",'
    sJ = sJ..'"count10_um":"'..d['count10_um']..'"'
    sJ = sJ..'},'
    sJ = sJ..'"BMP":{'
    sJ = sJ..'"T":"'..sT..'",'
    sJ = sJ..'"QFE":"'..sQFE..'",'
    sJ = sJ..'"QNH":"'..sQNH..'",'
    sJ = sJ..'"pressure":"'..sPressure..'",'
    sJ = sJ..'"humidity":"'..sHumidity..'",'
    sJ = sJ..'"dev_point":"'..sDew_point..'"'
    sJ = sJ..'}}'
    return sJ
end -- buildJSON

----------------------------------------------------------------------------------
-- funzione per leggere i valori del sensore BME280/BMP280 (temp, press..)
function readBME()
    sda, scl = 3, 4
    i2c.setup(0, sda, scl, i2c.SLOW) -- call i2c.setup() only once
    local mode = bme280.setup()
    tmr.delay(1000000) -- 1second
    if mode == 1 then
        -- print("bmp280")
        T, P, H, QNH = bme280.read(alt)
        if T == nil or P == nil or H == nil or QNH == nil then return end -- if fail to read bme
        local Tsgn = (T < 0 and -1 or 1); T = Tsgn*T
        sT = string.format("%s%d.%02d", Tsgn<0 and "-" or "", T/100, T%100)
        sQFE = string.format("%d.%03d", P/1000, P%1000)
        sQNH = string.format("%d.%03d", QNH/1000, QNH%1000)
        MHG = P / 133,3
        sPressure = string.format("%d.%02d", MHG/10 , MHG%10)
        -- altimeter function - calculate altitude based on current sea level pressure (QNH) and measure pressure
        P = bme280.baro()
        curAlt = bme280.altitude(P, QNH)
        local curAltsgn = (curAlt < 0 and -1 or 1); curAlt = curAltsgn*curAlt
        sAltitude = string.format("%s%d.%02d", curAltsgn<0 and "-" or "", curAlt/100, curAlt%100)
        return sT, sQFE, sQNH, sPressure
    elseif mode == 2 then
        -- print("bme280")
        T, P, H, QNH = bme280.read(alt)
        if T == nil or P == nil or H == nil or QNH == nil then return end -- if fail to read bme
        local Tsgn = (T < 0 and -1 or 1); T = Tsgn*T
        sT = string.format("%s%d.%02d", Tsgn<0 and "-" or "", T/100, T%100)
        sQFE = string.format("%d.%03d", P/1000, P%1000)
        sQNH = string.format("%d.%03d", QNH/1000, QNH%1000)
        MHG = P / 133,3
        sPressure = string.format("%d.%02d", MHG/10 , MHG%10)
        sHumidity = string.format("%d.%03d", H/1000, H%1000)
        D = bme280.dewpoint(H, T)
        local Dsgn = (D < 0 and -1 or 1); D = Dsgn*D
        sDew_point = string.format("%s%d.%02d", Dsgn<0 and "-" or "", D/100, D%100)
        -- altimeter function - calculate altitude based on current sea level pressure (QNH) and measure pressure
        P = bme280.baro()
        curAlt = bme280.altitude(P, QNH)
        local curAltsgn = (curAlt < 0 and -1 or 1); curAlt = curAltsgn*curAlt
        sAltitude = string.format("%s%d.%02d", curAltsgn<0 and "-" or "", curAlt/100, curAlt%100)
        return sT, sQFE, sQNH, sPressure, sHumidity, sDew_point
     else
         print("no device BMx280")
     end
end -- readBME

----------------------------------------------------------------------------------
-- funzione per mettersi in ascolto del sensore di inquinamento
function listenPM(mode)
    if mode == false then
        uart.on("data") -- unregister callback function
    elseif mode == true then
        uart.on("data", 31,
            function(data)
                aqi = parse(data)
                if aqi == nil then
                    return
                end
                sJSON = buildJSON(aqi)
                print(sJSON)
                putValue(sJSON)
            end, 0) -- function
    end
end -- listenPM

----------------------------------------------------------------------------------
-- Execution starts here...

initUART(9600)
initWIFI(ssid, pass)
