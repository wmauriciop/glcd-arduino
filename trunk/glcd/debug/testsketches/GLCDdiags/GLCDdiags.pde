/*
 * GLCDdiags
 *
 * vi:ts=4
 *
 * This sketch will test the memory and interface to the GLCD module as well as report
 * current GLCD library configuration information to the serial port.
 *
 * The memory associated with each chip will be tested seperately.
 * Tests will be performed starting on chip #0.
 * The GLCD will go through a series of visual displays as the memory is
 * being tested. The test will attempt to display the chip # under test as
 * well as the x coordinate values under test using the memory and chip that is not under test.
 * If everthing is working and configured properly, chip #0 will be on the left
 * and each increasing chip # will advance to the right.
 *
 * Status and error information will also sent out the serial port while testing.
 *
 * The test peforms a few different memory tests but the main tests walk an incrementing pattern
 * through memory horizontally by incrementing through pages column at a time (left to right)
 * as well as vertically by incrementing throuh pages page a time (top to bottom).
 * 
 */


#include <glcd.h>
#include "include/glcd_io.h"
#include "fonts/SystemFont5x7.h"       // system font

#define countdown(x) delay(x * 1000)

#define glcd_CHIP_COUNT ((DISPLAY_WIDTH + CHIP_WIDTH - 1)  / CHIP_WIDTH) // round up if width is not evenly divisable
#define MAX_ERRORS 10


char *hline = "-----------------------------------------------------\n";
/*
 * Define a REAL printf since Arduino doesn't have one
 */

extern "C" {int serialputc(char c, FILE *fp) { Serial.write(c); }}

void SerialPrintf(const char *fmt, ...)
{
FILE stdiostr;

	va_list ap;

	fdev_setup_stream(&stdiostr, serialputc, NULL, _FDEV_SETUP_WRITE);

	va_start(ap, fmt);
	vfprintf(&stdiostr, fmt, ap);
	va_end(ap);
}

/*
 * Define an eprintf() function for error output
 * (map it to the SerialPrintf() defined above)
 */
#define eprintf(...) SerialPrintf(__VA_ARGS__)


void
setup()
{
	Serial.begin(9600);

#ifdef CORE_TEENSY
	delay(500);    // allow USB time to come up.
#endif

	Serial.print("Serial initialized\n");

	delay(5);    // allow the hardware time settle

	GLCD.Init();   // initialise the library, non inverted writes pixels onto a clear screen

  	GLCD.SelectFont(System5x7, BLACK);

	/*
	 * dump the GLCD library configuration information to
	 * the serial port.
	 */
	showGLCDconfig();

}

void  loop()
{   // run over and over again

int lcount = 0;

	while(1)
	{
		SerialPrintf(hline);
		SerialPrintf("Diag Loop: %d\n", lcount);
		if( lcdmemtest())
		{
			/*
			 * memory tests failed.
			 */
			eprintf("TEST FAILED\n");
		}
		else
		{
			SerialPrintf("Tests PASSED\n");
			GLCD.ClearScreen();
			GLCD.CursorTo(0,0);
			GLCD.print("Tests PASSED");
		}

		delay(5000);
		lcount++;
		GLCD.ClearScreen();
	}
}


uint8_t lcdmemtest(void)
{
uint8_t errors = 0;

	SerialPrintf("Walking 1s data test\n");

	errors = lcdw1test();
	if(errors)
		return(errors);

	SerialPrintf("Write/Read Chip Select Test\n");

	errors = lcdw1test();
	if(errors)
		return(errors);

	GLCD.ClearScreen();

	SerialPrintf("testing GLCD memory pages\n");

	uint8_t col = 0;
	uint8_t ecol = CHIP_WIDTH-1;
	for(uint8_t chip = 0; chip < glcd_CHIP_COUNT; chip++)
	{

		if(col >= CHIP_WIDTH)
			GLCD.CursorToXY(0,0);
		else
			GLCD.CursorToXY(CHIP_WIDTH,0);
		GLCD.print("Chip:");
		GLCD.print((int)chip);

		/*
		 * Assumes font is 8 pixels high
		 */
		if(col >= CHIP_WIDTH)
			GLCD.CursorToXY(0,8);
		else
			GLCD.CursorToXY(CHIP_WIDTH,8);
		GLCD.print((int)col);
		GLCD.print("-");
		GLCD.print((int)ecol);
		delay(500);

		SerialPrintf("Horizonal Page Test Chip: %d Pixels %d to %d\n", chip, col, ecol);
		errors += lcdhpagetest(col, ecol, 0, GLCD.Height/8 - 1, 0, 255);
		SerialPrintf("Vertical Page Test Chip: %d Pixels %d to %d\n", chip, col, ecol);
		errors += lcdvpagetest(col, ecol, 0, GLCD.Height/8 - 1, 0, 255);
		GLCD.ClearScreen();

		col += CHIP_WIDTH;
		ecol += CHIP_WIDTH;
		if(ecol > GLCD.Right)
			ecol = GLCD.Right;
	}


	GLCD.CursorTo(0,0);
	GLCD.print("Full Display");
	GLCD.CursorTo(0,1);
	GLCD.print((int)0);
	GLCD.print("-");
	GLCD.print((int)GLCD.Right);
	delay(1000);
	SerialPrintf("Full Module Horizontal Page Test:Pixels %d to %d\n",  0, GLCD.Right);
	errors += lcdhpagetest(0, GLCD.Right, 0, GLCD.Bottom/8, 0, 255);
	SerialPrintf("Full Module Vertical Page Test:Pixels %d to %d\n",  0, GLCD.Right);
	errors += lcdvpagetest(0, GLCD.Right, 0, GLCD.Bottom/8, 0, 255);

	GLCD.ClearScreen();

	return(errors);
}

/*
 * Walk a bit through a single memory location to see if
 * basic reads/writes work.
 */

uint8_t
lcdw1test(void)
{
uint8_t errors = 0;
uint8_t data;

	for(uint8_t pat = 1;  pat != 0; pat <<= 1)
	{
		GLCD.GotoXY(0,0);
		GLCD.WriteData(pat);
		GLCD.GotoXY(0,0);
		data = GLCD.ReadData();

		if(data != pat)
		{
			eprintf("Compare error: %x != %x\n", data, pat);
			errors++;
		}
	}
	return(errors);
}

/*
 * LCD read/write chip select test.
 * This test attempts to detect chip select issues by writing the chip number
 * to the lowest page of memory for each chip.
 * This is done incrementing and decrementing.
 * It must be done both ways because when chip selects are wrong, it is possible
 * to write to more than 1 chip at a time. To catch this, you have write do the operation
 * more tha once. Once by writing incrementing addresses and then decrementing addresses.
 */

uint8_t
lcdrwseltest()
{
uint8_t errors = 0;
uint8_t data;


	for(uint8_t chip = 0, addr = 0; chip < glcd_CHIP_COUNT; chip++, addr += CHIP_WIDTH)
	{
		GLCD.GotoXY(addr, 0);
		GLCD.WriteData(chip);
	}
	for(uint8_t chip = 0, addr = 0; chip < glcd_CHIP_COUNT; chip++, addr += CHIP_WIDTH)
	{
		GLCD.GotoXY(addr, 0);
		data = GLCD.ReadData();
		if(data != chip)
		{
			eprintf("Compare error: chip:%d  %x != %x\n", chip, data, chip);
			errors++;
		}
	}

	for(int chip = glcd_CHIP_COUNT - 1, addr = (glcd_CHIP_COUNT-1)*CHIP_WIDTH; chip >= 0; chip--, addr -= CHIP_WIDTH)
	{
		GLCD.GotoXY(addr, 0);
		GLCD.WriteData(chip);
	}
	for(int chip = glcd_CHIP_COUNT - 1, addr = (glcd_CHIP_COUNT-1)*CHIP_WIDTH; chip >= 0; chip--, addr -= CHIP_WIDTH)
	{
		GLCD.GotoXY(addr, 0);
		data = GLCD.ReadData();
		if(data != chip)
		{
			eprintf("Compare error: chip:%d  %x != %x\n", chip, data, chip);
			errors++;
		}
	}

	return(errors);
}


/*
 * Walk incrementing values through incrementing memory locations.
 * 
 * A value starting at sval ending at eval will be walked through memory
 * pages horizontally.
 * The starting x location will be filled in with sval and the value will
 * incremented through all locations to be tested. Values are written through
 * incrementing x values and when the maximum x value is reached on a row/page,
 * writing is continued down on the next row/page.
 *
 * All the values are read and compared to expected values.
 *
 * Then process starts over again by incrementing the starting value.
 * This repeats until the starting value reaches the ending value.
 *
 * Each memory location will tested with an incrementing value evel-sval+1 times.
 *
 * If sval is 0 and eval is 255, every memory location will be tested for every value.
 *
 */

 
int lcdhpagetest(uint8_t x1, uint8_t x2, uint8_t spage, uint8_t epage, uint8_t sval, uint8_t eval)
{
uint8_t x;
uint8_t data;
uint8_t rdata;
uint8_t page;
uint8_t errors = 0;

	/*
	 * perform each interation of test across memory with an incrementing pattern
	 * starting at sval and bumping sval each iteration.
	 */
	do
   	{
		/*
		 * write out all glcd memory pages
		 * sequentially through incrementing columns (x values)
		 */

		data = sval;
		for(page = spage; page <= epage; page++)
		{

			GLCD.GotoXY(x1, page * 8);
			for(x = x1; x <= x2; x++)
			{
				/*
				 * GotoXY() is intentially not done here in the loop to 
				 * let the hardware bump its internal address.
				 * This ensures that the glcd code and hardware are
				 * properly tracking each other.
				 */
			    GLCD.WriteData(data);
			    data++;
			}
		}

		/*
		 * Now go back and verify the pages
		 */

		data = sval;
		for(page = spage; page <= epage; page++)
		{

			for(x = x1; x<= x2; x++)
			{
				/*
				 * Reads don't auto advance X
				 */
				GLCD.GotoXY(x, page * 8);
				rdata = GLCD.ReadData();

				if(data != rdata)
				{
					eprintf("Verify error: (%d,%d) %x!=%x\n",
						x, spage*8, data, rdata);
					if(++errors > MAX_ERRORS)
						return(errors);
				}
				data++;
			}
		}
    } while(sval++ != eval);
	return(0);
}

/*
 * Walk incrementing values through vertical memory page locations.
 * 
 * A value starting at sval ending at eval will be walked through memory pages
 * Vertically.
 * The starting x location will be filled in with sval and the value will
 * incremented through all memory pages to be tested. Values are written through
 * incrementing row/page values and when the maximum row/page value is reached,
 * writing is continued at the top page of the next column/x location.
 *
 * All the values are read and compared to expected values.
 *
 * Then process starts over again by incrementing the starting value.
 * This repeats until the starting value reaches the ending value.
 *
 * Each memory location will tested with an incrementing value evel-sval+1 times.
 *
 * If sval is 0 and eval is 255, every memory location will be tested for every value.
 *
 */

 
int lcdvpagetest(uint8_t x1, uint8_t x2, uint8_t spage, uint8_t epage, uint8_t sval, uint8_t eval)
{
uint8_t x;
uint8_t data;
uint8_t rdata;
uint8_t page;
uint8_t errors = 0;

	/*
	 * perform each interation of test across memory with an incrementing pattern
	 * starting at sval and bumping sval each iteration.
	 */
	do
   	{
		/*
		 * write out all glcd memory pages
		 * sequentially through incrementing columns (x values)
		 */

		data = sval;
		for(x = x1; x <= x2; x++)
		{
			for(page = spage; page <= epage; page++)
			{
				GLCD.GotoXY(x, page * 8);
			    GLCD.WriteData(data);
			    data++;
			}
		}

		/*
		 * Now go back and verify the pages
		 */

		data = sval;
		for(x = x1; x<= x2; x++)
		{
			for(page = spage; page <= epage; page++)
			{
				GLCD.GotoXY(x, page * 8);
				rdata = GLCD.ReadData();

				if(data != rdata)
				{
					eprintf("Verify error: (%d,%d) %x!=%x\n",
						x, spage*8, data, rdata);

					if(++errors > MAX_ERRORS)
						return(errors);
				}
				data++;
			}
		}
    } while(sval++ != eval);
	return(0);
}

/*
 * Dump the GLCD configuration information out
 * the serial port.
 */

void showGLCDconfig(void)
{
	
	SerialPrintf(hline);
	SerialPrintf("GLCD Library Configuration: Library VER: %d\n", GLCD_VERSION);
	SerialPrintf(hline);
	SerialPrintf("DisplayWidth:%3d DisplayHeight:%2d\n", GLCD.Height, GLCD.Width);
	SerialPrintf("ChipWidth:%3d ChipHeight:%2d\n", CHIP_WIDTH, CHIP_HEIGHT);
	SerialPrintf("#Chips:%d", glcd_CHIP_COUNT);

#ifdef glcdCSEL1
	SerialPrintf(" CSEL1:%s", glcdpin2str(glcdCSEL1));
#endif
#ifdef glcdCSEL2
	SerialPrintf(" CSEL2:%s", glcdpin2str(glcdCSEL2));
#endif
#ifdef glcdCSEL3
	SerialPrintf(" CSEL3:%s", glcdpin2str(glcdCSEL3));
#endif
#ifdef glcdCSEL4
	SerialPrintf(" CSEL4:%s", glcdpin2str(glcdCSEL4));
#endif

	SerialPrintf(" RW:%s", glcdpin2str(glcdRW));
	SerialPrintf(" DI:%s", glcdpin2str(glcdDI));

#ifdef glcdEN
	SerialPrintf(" EN:%s", glcdpin2str(glcdEN));
#endif

#ifdef glcdE1
	SerialPrintf(" E1:%s", glcdpin2str(glcdE1));
#endif
#ifdef glcdE2
	SerialPrintf(" E2:%s", glcdpin2str(glcdE2));
#endif

	SerialPrintf("\n");

	SerialPrintf("D0:%s", glcdpin2str(glcdData0Pin));
	SerialPrintf(" D1:%s", glcdpin2str(glcdData1Pin));
	SerialPrintf(" D2:%s", glcdpin2str(glcdData2Pin));
	SerialPrintf(" D3:%s", glcdpin2str(glcdData3Pin));
	SerialPrintf(" D4:%s", glcdpin2str(glcdData4Pin));
	SerialPrintf(" D5:%s", glcdpin2str(glcdData5Pin));
	SerialPrintf(" D6:%s", glcdpin2str(glcdData6Pin));
	SerialPrintf(" D7:%s", glcdpin2str(glcdData7Pin));

	SerialPrintf("\n");


	SerialPrintf("tDDR:%d tAS:%d tDSW:%d tWH:%d tWL: %d\n",
		GLCD_tDDR, GLCD_tAS, GLCD_tDSW, GLCD_tWH, GLCD_tWL);
	/*
	 * Show GLCD data mode
	 *
	 * Requires getting down and dirty and mucking around done
	 * in avrio land.
	 */

	SerialPrintf("Data mode: ");
	/*
	 * First check for full 8 bit mode
	 *
	 */
	if(AVRDATA_8BIT(glcdData0Pin, glcdData1Pin, glcdData2Pin, glcdData3Pin,
		glcdData4Pin, glcdData5Pin, glcdData6Pin, glcdData7Pin))
	{
		/*
		 * full 8 bit mode
		 */
		SerialPrintf("byte\n");
	}
	else
	{
		SerialPrintf("\n d0-d3:");
		if(AVRDATA_4BITHI(glcdData0Pin, glcdData1Pin, glcdData2Pin, glcdData3Pin) ||
			AVRDATA_4BITLO(glcdData0Pin, glcdData1Pin, glcdData2Pin, glcdData3Pin))
		{
			SerialPrintf("nibble mode");
#ifndef GLCD_ATOMIC_IO
			SerialPrintf("-Non-Atomic");
#else
			SerialPrintf("-disabled"); // for now this "knows" avrio disabled nibbles when in atomic mode.
#endif
		}
		else
		{
			SerialPrintf("bit i/o");
		}

		SerialPrintf("\n d4-d7:");
	
		if(AVRDATA_4BITHI(glcdData4Pin, glcdData5Pin, glcdData6Pin, glcdData7Pin) ||
			AVRDATA_4BITLO(glcdData4Pin, glcdData5Pin, glcdData6Pin, glcdData7Pin))
		{
			SerialPrintf("nibble mode");
#ifndef GLCD_ATOMIC_IO
			SerialPrintf("-Non-Atomic");
#else
			SerialPrintf("-disabled"); // for now this "knows" avrio disabled nibbles when in atomic mode.
#endif
		}
		else
		{
			SerialPrintf("bit i/o");
		}
		SerialPrintf("\n");
	}

	/*
 	 * Show font rendering:
	 */

	SerialPrintf("Text Render: ");
#ifdef GLCD_OLD_FONTDRAW
	SerialPrintf("OLD\n");
#else
	SerialPrintf("NEW\n");
#endif

	/*
	 * show no scroll down if disabled.
	 */

#ifdef GLCD_NO_SCROLLDOWN
	SerialPrintf("NO Down Scroll");
#endif

}

char *
glcdpin2str(uint16_t pin)
{
static char buf[8];

#ifdef _AVRIO_AVRIO_

	if(pin >= AVRIO_PIN(AVRIO_PORTA, 0))
	{
		sprintf(buf, "0x%x", pin);
	}
	else
#endif
	{
		sprintf(buf, "%d", pin);
	}
	return(buf);
}
