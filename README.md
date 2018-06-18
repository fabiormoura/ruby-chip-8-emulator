# References

* https://github.com/badlogic/chip8/blob/master/roms/pong.rom
* http://devernay.free.fr/hacks/chip8/C8TECH10.HTM#memmap
* http://www.multigesture.net/articles/how-to-write-an-emulator-chip-8-interpreter/

# ruby-chip-8-emulator

Memory
 - 4KB (4,096 bytes)
 - 0x000 (0) to 0xFFF (4095)
 - The first 512 bytes, from 0x000 to 0x1FF, reserved space
 - most ROMs start at 0x200 (512) but some begin at 0x600 (1536). Programs beginning at 0x600 are intended for the ETI 660 computer.

  0x000-0x1FF - Chip 8 interpreter (contains font set in emu)
  0x050-0x0A0 - Used for the built in 4x5 pixel font set (0-F)
  0x200-0xFFF - Program ROM and work RAM
  
---
  
ROM Registers
 - 16 registers
 - 8 bit (1Byte) each
 - usually referred to as Vx, where x is a hexadecimal digit (0 through F)
 - VF not used by ROMs, as it is used as a flag by some instructions.
 
Store Memory Addresses Register
 - Special 16-bit register called I. This register is generally used to store memory addresses, so only the lowest (rightmost) 12 bits are usually used
 
Sound and Delay Timer Registers
 - Two additional registers for the delay and sound timers. When these registers are non-zero, they are automatically decremented at a rate of 60Hz.
 
Program Counter Register 
 - The program counter (PC) should be 16-bit, and is used to store the currently executing address.
 
Stack and Stack Register
 - The stack pointer (SP) can be 8-bit, it is used to point to the topmost level of the stack. 
 - The stack is an array of 16 16-bit values, used to store the address that the interpreter should return to when finished with a subroutine.

---

Inputs
 - 16 Keys
 - 0 - F hexadecimal
 
---

Display

 - 64x32-pixel monochrome
 (0,0)       (63,0)
 (0,31)      (63,31)
 
Sprites
 - 15 bytes. for a possible sprite size of 8x15
 - fonts: 5 bytes or 8x5 pixels. Stored in (0x000 to 0x1FF)
 
--------
Delay and Sound Timers

Chip-8 provides 2 timers, a delay timer and a sound timer.

The delay timer is active whenever the delay timer register (DT) is non-zero. This timer does nothing more than subtract 1 from the value of DT at a rate of 60Hz. When DT reaches 0, it deactivates.

The sound timer is active whenever the sound timer register (ST) is non-zero. This timer also decrements at a rate of 60Hz, however, as long as ST's value is greater than zero, the Chip-8 buzzer will sound. When ST reaches zero, the sound timer deactivates.

The sound produced by the Chip-8 interpreter has only one tone. The frequency of this tone is decided by the author of the interpreter.


-----
Instructions
 - 2 bytes
 
 
