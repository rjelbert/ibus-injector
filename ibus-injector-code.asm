	title  "ibus-injector-code"

; Project to read i/o pins and output serial i-bus commands 
; at 9600 8E1
; using i-bus device source id "F2" for the moment
 
; Hardware Notes:
; 16F648A with internal 4MHz internal osc

; RA0 - * OUTPUT - RED LED1 (active LOW) "DATA COLLISION"
; RA1 - I/O INPUT A
; RA2 - I/O INPUT B
; RA3 - I/O INPUT C
; RA4 - I/O INPUT D
; RA5 - input (_MCLR) not used
; RA6 - XTAL 4MHz
; RA7 - XTAL 4MHz

; RB0 - * INPUT ALSO connected RB0 (SERIAL RX)
; RB1 - * INPUT SERIAL RX data
; RB2 - * OUTPUT SERIAL TX data
; RB3 - OUTPUT unused
; RB4 - OUTPUT unused
; RB5 - * OUTPUT - GREEN LED2 (active LOW) "DATA TRANSMIT"
; RB6 - OUTPUT - PGC/unused
; RB7 - OUTPUT - PGD/unused

  list P=16F648A
  errorlevel 0,-305
  INCLUDE "C:\Program Files\Microchip\MPASM Suite\P16F648A.inc"
	__CONFIG H'3F09'

	PAGE

; Define pins here for use in bit operations
; port A
#DEFINE REDLED		PORTA,0		; the GREEN LED (active LOW)
; port B
#DEFINE GREENLED 	PORTB,5		; the RED LED (active LOW)
 
; Define general purpose file registers here
count		equ 20h		; this is the counter for timing delays
counthi		equ	21h		; this is the hi-byte for the timing counter
pres		equ 22h		; file register to preserve registers (temp)
txdatapres	equ	23h		; temp file for txdata to store w
disptemp	equ 24h		; temp register for the display routine
paritytemp	equ	25h		; temp working file for calculating parity
dataout		equ	26h		; file to store data to be sent out
xortemp		equ	27h		; file to generate packet xor checksum
waitclearcountinner	equ	28h
waitclearcountouter	equ	29h	
rxvalid		equ	2Ah		; flag if rxdata is valid
rawinput	equ	2Bh		; file to store the input data from port A pins
dataouttemp	equ	2Ch		; file for dataout temp logic function
lastdataout	equ	2Dh		; remember the last value output
parity		equ	70h		; temp file for the parity calculation. LSB is parity after exit

; Main code thread starts here

	org    0

; set up control registers

; TRISB configure port b (bank 1)
	bsf		STATUS, RP0
	movlw	b'00000111'	; portb ('1' input)
	movwf	TRISB
; SPBRG (bank 1)
	movlw	d'25'		; set up SPGRB baud rate (25 = 9600 baud at 4 MHz)
	movwf	SPBRG	
; TXSTA (bank 1)
	movlw	b'01100110'	; set up TXSTA serial tx options (BRGH=1)
	movwf	TXSTA
	bcf		STATUS, RP0
; RCSTA serial config (bank 0)
	movlw	b'11010000'	; set up RCSTA serial rx options
	movwf	RCSTA		; this one is in bank 0
; PIE1 register (bank 1)
	bsf		STATUS, RP0
	movlw	b'00000000'
	movwf	PIE1
	bcf		STATUS, RP0

; **** BANK 0 REGISTERS ****
	bcf		STATUS, RP0	; select register page 0
; CMCOM port A i/o control
	movlw	b'00000111'	; CMCON - comparators OFF
	movwf	CMCON
; INTCON register
	movlw	b'00000000'
	movwf	INTCON
; PIR interrupr flags
	movlw	b'00000000'
	movwf	PIR1
; **** BANK 1 REGISTERS ****
	bsf		STATUS, RP0	; select register page 1
; OPTION_REG register
	movlw	b'10000000'	; disable pull-ups on port b
	movwf	OPTION_REG
; PCON power on stuff
	movlw	b'0001000'
	movwf	PCON
; TRISA configure porta		
	movlw	b'00111110'	; porta ('1' input)
	movwf	TRISA
; VRCON comparators vref control - set to OFF
	movlw	b'00000000'	; VRCON - vref OFF
	movwf	VRCON
; end of config
	bcf		STATUS, RP0	; select register page 0

; **** MAIN CODE STARTS HERE ****

; set up initial states for ports a and b
	movlw	b'00000000'	; set up initial states for porta
	movwf	PORTA		; 
	movlw	b'00000000'	; set up initial states for portb
	call	delay
	movwf	PORTB		; 
	bsf		REDLED		; off
	bsf		GREENLED	; off	
	
	movlw	b'00000000'	; preload the last transmitted data
	movwf	dataout		; this forces a valid write on power up
	movlw	b'00001111'	; preload the last output value
	movwf	lastdataout	; makes the last different to the current

; main program loop here

mainloop
; grab the current inputs from the port A pins

	movfw	PORTA		; read port A all 8 bits
	movwf	rawinput	; save it
	rrf		rawinput, 1	; shift data left by 1 bit to fit to bottom nibble
	comf	rawinput, 1	; invert the inputs because of opto isolator inversion
	movlw	b'00001111'	; this is a mask
	andwf	rawinput, 1 ; mask against just the inputs we are expecting	
	movfw	rawinput	; load it back into w
	movwf	dataout		; prepare dataout as the next data to send

; is dataout different to lastdataout? if yes then send it!

	movfw	dataout		; load it
	movwf	dataouttemp	; save it in the temp file
	movfw	lastdataout	; load the last transmitted byte
	subwf	dataouttemp, 1	; sub one from the other
	btfsc	STATUS, Z	; test for zero
	goto	mainloop	; do this if the port has not changes

; note that there is no debounce in this at the moment.

waitclear
; wait in here for the i-bus to be quiet for more than 1 byte @ 9600baud
; equating roughly to 1200uS or 1.25ms. Each processor cycle is 1uS
;	goto skipthis
	movlw	d'1'	; only goes through one time with 1. Might take out outer loop later...
	movwf	waitclearcountouter
waitclearloopouter
	movlw	d'255' ; the number of loop cycles to wait 
	movwf	waitclearcountinner
waitclearloopinner
	btfss	PORTB, 0 ; test the receive bit
	goto	waitclear
	decfsz	waitclearcountinner, 1
	goto	waitclearloopinner		
	decfsz	waitclearcountouter, 1
	goto	waitclearloopouter
skipthis
	
	bcf		GREENLED	; green led on to signify start tx of packet

; read data from inputput fifo to clear it - we are about to send	
	call	rxreset
	movfw	RCREG			; read data from serial port into 'w'
	movfw	RCREG			; read data from serial port into 'w'

sendpacket
;	current format is: F2 04 BF 00 dd CK
;	source length destination command data checksum
	
	clrf	xortemp	; reset the xor checksum

	movlw 	h'F2'	; the sender module id code
	xorwf	xortemp, 1
	call 	txdata
	btfsc	rxvalid, 0 ; check to see if byte was sent OK, if not start again
	goto	waitclear	; collision so start packet again	
	movlw 	h'04'	; the length of the packet (5 with seq - see below)
	xorwf	xortemp, 1
	call 	txdata
	btfsc	rxvalid, 0
	goto	waitclear	; collision so start packet again
	movlw 	h'F3'		; was BF (GLOBAL) set to another false id
	xorwf	xortemp, 1
	call	txdata
	btfsc	rxvalid, 0
	goto	waitclear	; collision so start packet again

	movlw	b'00000000'
	xorwf	xortemp, 1
	call	txdata
	btfsc	rxvalid, 0
	goto	waitclear	; collision so start packet again

	movfw	dataout 
	xorwf	xortemp, 1
	call	txdata
	btfsc	rxvalid, 0
	goto	waitclear	; collision so start packet again
	movfw	xortemp 
	call	txdata
	btfsc	rxvalid, 0
	goto	waitclear	; collision so start packet again

	movfw	dataout
	movwf	lastdataout	; it was sent ok so set lastdataout as dataout

	bsf		GREENLED ; green led off
	bsf		REDLED ; red led off
	goto 	mainloop
	
; :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
; ::::::::::::::::::::::::::: SUB ROUTINES ::::::::::::::::::::::::::::
; :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

txdata						; send 'w' to i-bus and check for collisions
	movwf	txdatapres		; preserve the byte to send		
	call	generateparity	; call sub to generate parity bit
	bsf		STATUS, RP0		; select bank 1
	bcf		TXSTA, TX9D		; clear tx bit 9 (parity) by default
	btfsc	parity, 0
	bsf		TXSTA, TX9D		; set the parity bit if needed			
	bcf		STATUS, RP0		; select bank 0 again
	movwf	TXREG			; send w out
; wait for the byte to get transmitted
	bsf		STATUS, RP0		; select bank 1
	btfss	TXSTA, TRMT		; test for end of transmission
	goto	$-1
	bcf		STATUS, RP0		; select bank 0 again

; short delay while data is fully received in the RX register
	movlw	d'18'
	movwf	count
delayloopsm
	decfsz	count
	goto	delayloopsm

; now read the just-sent data

	bcf		rxvalid, 0			; reset the valid flag to VALID = 0 = yes, is valid
	movlw	d'0'			; load w with zero

	btfsc	RCSTA,	FERR	; is there a framing error
	bsf		rxvalid, 0

readback
	movfw	RCREG			; read data from serial port into 'w'

	btfsc	RCSTA,	OERR	; test to see if there is an overrun error
	call	rxreset			; reset the usart rx (read up on this)
	
; compare txdatapres with byte received. These should be the same if no colisions!

	subwf	txdatapres, 1
	btfss	STATUS, Z		; check z to see if zero
	bsf		rxvalid, 0		; set as invalid

; compare parity bit 0 with RX parity bit 
; inspect parity sent

	btfsc	parity, 0
	goto	needparity1
	btfsc	RCSTA, RX9D
	bsf		rxvalid, 0
	goto	endtests
needparity1
	btfss	RCSTA, RX9D
	bsf		rxvalid, 0
endtests
	btfsc	rxvalid, 0
	goto	goterror
	return	
goterror
	bcf		REDLED
	return

; **************************
rxreset
	bcf		RCSTA,	CREN	; clear CREN	
	bsf		RCSTA,	CREN	; set CREN to enable RX again and clear overrun error	
	return
; **************************
delay
	movwf	pres		; preserve w
	movlw	.255		;  Delay counter
	movwf	count
	movlw	.255
	movwf	counthi
delay_loop
	decfsz 	count
   	goto	delay_loop
	movlw	.255
	movwf	count	; reload counter
	decfsz	counthi
	goto	delay_loop
   	movf	pres, 0
	return
; ***************************
generateparity
; this is the best / smallest parity generator I can find
; on exit, lsb of parity contains the even parity bit,
; the rest contains junk
	movwf	pres
	movwf	parity
	swapf	parity, 0
	xorwf	parity, 1
	rrf		parity, 0
	xorwf	parity, 1
	btfsc	parity, 2
	incf	parity, 1
	movf	pres, 0 
	return

	end
