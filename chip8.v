module main

import crypto.rand
import gg
import gx

const (
	display_width     = 64
	display_height    = 32
	display_scale     = 4

	ram_size          = 0xFFFF
	stack_size        = 0x16
	variables_size    = 0x10
	keyboard_size     = 0x10

	instruction_size  = 2

	digit_sprite_size = 5

	digit_sprite_data = [
		0xF0,
		0x90,
		0x90,
		0x90,
		0xF0 /* 0 */,
		0x20,
		0x60,
		0x20,
		0x20,
		0x70 /* 1 */,
		0xF0,
		0x10,
		0xF0,
		0x80,
		0xF0 /* 2 */,
		0xF0,
		0x10,
		0xF0,
		0x10,
		0xF0 /* 3 */,
		0x90,
		0x90,
		0xF0,
		0x10,
		0x10 /* 4 */,
		0xF0,
		0x80,
		0xF0,
		0x10,
		0xF0 /* 5 */,
		0xF0,
		0x80,
		0xF0,
		0x90,
		0xF0 /* 6 */,
		0xF0,
		0x10,
		0x20,
		0x40,
		0x40 /* 7 */,
		0xF0,
		0x90,
		0xF0,
		0x90,
		0xF0 /* 8 */,
		0xF0,
		0x90,
		0xF0,
		0x10,
		0xF0 /* 9 */,
		0xF0,
		0x90,
		0xF0,
		0x90,
		0x90 /* A */,
		0xE0,
		0x90,
		0xE0,
		0x90,
		0xE0 /* B */,
		0xF0,
		0x80,
		0x80,
		0x80,
		0xF0 /* C */,
		0xE0,
		0x90,
		0x90,
		0x90,
		0xE0 /* D */,
		0xF0,
		0x80,
		0xF0,
		0x80,
		0xF0 /* E */,
		0xF0,
		0x80,
		0xF0,
		0x80,
		0x80 /* F */,
	]
)

struct Chip8 {
mut:
	ram            [65535]byte
	vram           [display_height][display_width]bool
	stack          [22]u16
	stack_position byte
	variables      [16]byte
	keyboard       [16]bool
	// i register
	i u16
	// delay timer
	dt u8
	// sound timer
	st u8
	// where the file ends
	end_point u16
	// game interface
	gg &gg.Context = 0
}

fn (c Chip8) get_instruction(pos u16) u16 {
	return (u16(c.ram[pos]) << 8) + c.ram[pos + 1]
}

// fills the beginning of the memory that isn't used by the interpreter
// with the digit data
fn (mut c Chip8) initialize_digits() {
	for i, data in digit_sprite_data {
		c.ram[i] = byte(data)
	}
}

fn (mut c Chip8) cycle() {
	instruction := c.get_instruction(c.stack[c.stack_position])
	opcode := instruction >> 12

	match opcode {
		0x0 {
			match instruction & 0xff {
				// clear the vram
				0xE0 {
					c.vram = [display_height][display_width]bool{}
				}
				// return from a subroutine
				0xEE {
					c.stack_position -= 1
					assert c.stack_position >= 0
				}
				else {}
			}
		}
		// jmp nnn - jump to address
		0x1 {
			c.stack[c.stack_position] = (instruction & 0xfff) - instruction_size
		}
		// call nnn - call subroutine at address
		0x2 {
			c.stack_position += 1
			assert c.stack_position <= stack_size
			c.stack[c.stack_position] = (instruction & 0xfff) - instruction_size
		}
		// SE xkk - skip next instruction if var x == kk
		0x3 {
			variable_value := c.variables[(instruction >> 8) & 0xf]
			value := instruction & 0xff

			if variable_value == value {
				c.stack[c.stack_position] += instruction_size
			}
		}
		// SNE xkk - skip next instruction if var x != kk
		0x4 {
			variable_value := c.variables[(instruction >> 8) & 0xf]
			value := instruction & 0xff

			if variable_value != value {
				c.stack[c.stack_position] += instruction_size
			}
		}
		// SE xy0 - skip next instruction if var x == y
		0x5 {
			x_value := c.variables[(instruction >> 8) & 0xf]
			y_value := c.variables[(instruction >> 4) & 0xf]

			if x_value == y_value {
				c.stack[c.stack_position] += instruction_size
			}
		}
		// LD xkk - load value kk into var x
		0x6 {
			value := byte(instruction & 0xff)
			c.variables[(instruction >> 8) & 0xf] = value
		}
		// ADD xkk - perform var x + kk and save in var x
		0x7 {
			value := byte(instruction & 0xff)
			c.variables[(instruction >> 8) & 0xf] += value
		}
		0x8 {
			variable_x := (instruction >> 8) & 0xf
			variable_y := (instruction >> 4) & 0xf

			match instruction & 0xf {
				// LD xy0 - loads var y into var x
				0x0 {
					c.variables[variable_x] = c.variables[variable_y]
				}
				// OR xy1 - perform bitwise or on var x and var y and save in
				// var x
				0x1 {
					c.variables[variable_x] |= c.variables[variable_y]
				}
				// AND xy2 - perform bitwise and on var x and var y and save in
				// var x
				0x2 {
					c.variables[variable_x] &= c.variables[variable_y]
				}
				// XOR xy3 - perform bitwise xor on var x and var y and save in
				// var x
				0x3 {
					c.variables[variable_x] ^= c.variables[variable_y]
				}
				// ADD xy4 - perform addition on var x and var y and save in
				// var x while setting var f to 1 if it results in a carry
				0x4 {
					result := u16(c.variables[variable_x]) + u16(c.variables[variable_y])
					c.variables[0xf] = byte(if result > 0xff { 1 } else { 0 })
					c.variables[variable_x] = byte(result & 0xff)
				}
				// SUB xy5 - perform addition on var x and var y and save in
				// var x while setting var f to 1 if var x is larger than var y
				0x5 {
					result := c.variables[variable_x] + c.variables[variable_y]
					c.variables[0xf] = byte(if c.variables[variable_x] > c.variables[variable_y] {
						1
					} else {
						0
					})
					c.variables[variable_x] = byte(result & 0xff)
				}
				// SHR xy6 - set var f to least significant bit then shift var x right
				0x6 {
					c.variables[0xf] = c.variables[variable_x] & 1
					c.variables[variable_x] >>= 1
				}
				// SUBN xy7 - perform addition on var x and var y and save in
				// var x while setting var f to 1 if var y is larger than var x
				0x7 {
					result := c.variables[variable_x] + c.variables[variable_y]
					c.variables[0xf] = byte(if c.variables[variable_x] < c.variables[variable_y] {
						1
					} else {
						0
					})
					c.variables[variable_x] = byte(result & 0xff)
				}
				// SHL xy8 - set var f to least significant bit then shift var x left
				0x8 {
					c.variables[0xf] = (c.variables[variable_x] >> 7) & 1
					c.variables[variable_x] <<= 1
				}
				else {
					println('Invalid instruction for 0x8 opcode $instruction')
					exit(1)
				}
			}
		}
		// SNE xy - skip next instruction if var x != var y
		0x9 {
			x_value := c.variables[(instruction >> 8) & 0xf]
			y_value := c.variables[(instruction >> 4) & 0xf]

			if x_value != y_value {
				c.stack[c.stack_position] += instruction_size
			}
		}
		// LD I nnn - load I with nnn
		0xA {
			c.i = instruction & 0xfff
		}
		// JP V0, addr - jump to var 0 + nnn
		0xB {
			c.stack[c.stack_position] = c.variables[0] + (instruction & 0xfff) - instruction_size
		}
		// RND x, kk - set var x to random number anded with kk
		0xC {
			c.variables[(instruction >> 8) & 0xf] = byte(rand.int_u64(256) or { return }) & byte(instruction & 0xff)
		}
		// DRW xyn - draw at var x (X), var y (Y), with sprite of length n at i register
		0xD {
			x := c.variables[(instruction >> 8) & 0xf]
			y := c.variables[(instruction >> 4) & 0xf]
			n := instruction & 0xf
			for i in 0 .. n {
				vram_y := (y + i) % display_height
				for j in 7 .. 0 {
					bit := (c.ram[c.i + i] >> j) & 1
					vram_x := (56 - x + byte(j)) % display_width
					collision := c.vram[vram_y][vram_x] && (bit == 1)
					c.variables[0xf] = c.variables[0xf] | byte(if collision { 1 } else { 0 })
					c.vram[vram_y][vram_x] = c.vram[vram_y][vram_x] != (bit == 1)
				}
			}
		}
		0xF {
			variable := (instruction >> 8) & 0xf
			match instruction & 0xff {
				// LD x07 - load dt into var x
				0x07 {
					c.variables[variable] = c.dt
				}
				// LD x0A - wait for key and then put value in var x
				// TODO: do this when keyboard is implemented
				0x08 {
					c.variables[variable] = 0
				}
				// LD x15 - set dt to var x
				0x15 {
					c.dt = c.variables[variable]
				}
				// LD x18 - set	st to var x
				0x18 {
					c.st = c.variables[variable]
				}
				// ADD x1E - add var x to i
				0x1E {
					c.i += c.variables[variable]
				}
				// LD F, Vx - set location of sprite in i according to var x
				0x29 {
					c.i = c.variables[variable] * digit_sprite_size
				}
				// LD B, Vx - load BCD representation of var x in i, i+1 and i+2
				0x33 {
					c.ram[c.i] = (c.variables[variable] / 100) % 10
					c.ram[c.i + 1] = (c.variables[variable] / 10) % 10
					c.ram[c.i + 2] = c.variables[variable] % 10
				}
				// LD I, Vx - stores var 0 through var x in memory starting at i
				0x55 {
					for i in 0 .. variable {
						c.ram[c.i + i] = c.variables[i]
					}
				}
				// LD Vx, I - store into var 0 through var x from memory
				// starting at i
				0x65 {
					for i in 0 .. variable {
						c.variables[i] = c.ram[c.i + i]
					}
				}
				else {}
			}
		}
		else {
			println('Unimplemented opcode: $opcode')
			exit(1)
		}
	}

	c.stack[c.stack_position] += instruction_size
}

fn frame(mut c Chip8) {
	c.gg.begin()
	c.gg.end()
}

fn main() {
	mut emulator := &Chip8{}
	emulator.gg = gg.new_context(
		bg_color: gx.rgb(0, 0, 0)
		width: (display_width * display_scale)
		height: (display_height * display_scale)
		create_window: true
		window_title: 'CHIP-8'
		frame_fn: frame
		user_data: emulator
	)
	emulator.gg.run()
}
