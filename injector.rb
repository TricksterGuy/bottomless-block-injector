# Not really 194, just 194 predetermined block configurations, really 120 puzzles.
NUM_PUZZLES = 194

PUZZLE_OFFSETS = 0x48000
PUZZLE_DATA_OFFSET_START = 0x184
PUZZLE_MOVES_OFFSET = 0x11235

PUZZLE_DATA = PUZZLE_OFFSETS + PUZZLE_DATA_OFFSET_START

# Contains data for a single puzzle
class PuzzleBuffer
    attr_accessor :moves
    attr_accessor :data
    
    def initialize(moves, data)
        @moves = moves
        @data = data
    end
    
    def at(r, c)
        raise "Invalid row %d column %d" % [r, c] unless r.between?(0, 11) and c.between?(0, 5)
        return @data[r * 6 + c]
    end
end

# Contains the entire database of puzzles in compressed format
class CompressedPuzzleData
    attr_accessor :buffer
    
    def initialize
        @buffer = []
        @byte = 0
        @byte_offset = 0
    end
    
    def add(trio)
        @byte = @byte |= trio << @byte_offset
        @byte_offset += 3
        if @byte_offset >= 8
            @buffer << (@byte & 0xFF)
            @byte = @byte >> 8
            @byte_offset = @byte_offset & 0x7
        end
    end
    
    def finish
        @buffer << (@byte & 0xFF)
        @byte = 0
        @byte_offset = 0
    end
    
    def size
        return @buffer.size
    end
    
    def offset
        return (@byte_offset << 13) | (self.size & 0x1FFF)
    end
end

def write_puzzle(index, moves, data)
	out = File.new("ta/#{index+1}.bbb", "wb+")
	# magic
	out.write("BBB\0")
	# version
	out.putc(1)
	out.putc(1)
	# type
	out.putc(0)
	# pad
	out.putc(0)
	# rows
	out.write([12].pack("l"))
	# columns
	out.write([6].pack("l"))
	# starting
	out.write([12].pack("l"))
	# moves
	out.write([moves].pack("l"))
	12.times do |i|
	    6.times do |j|
	        out.putc(data[[i, j]])
	    end
	end
	out.close
end

def read_puzzle(index)
	file = File.new("ta/#{index+1}.bbb", "rb+")
	# magic
	raise "ta/#{index}.bbb not a valid puzzle" if file.read(4) != "BBB\0"
	# version
	raise "ta/#{index}.bbb not version 1.1" if file.read(2) != "\001\001"
	# type
	raise "Can only inject Puzzle mode" if file.read(1) != "\000"
	# Padding byte
	file.read(1)
	# rows
	rows = file.read(4).unpack("l")[0]
	raise "Rows must be 12" if rows != 12
	# columns
	columns = file.read(4).unpack("l")[0]
	raise "Columns must be 6" if columns != 6
	# starting
	starting = file.read(4).unpack("l")[0]
	raise "Starting Rows must be 12" if starting != 12
	# moves
	moves = file.read(4).unpack("l")[0]
    raise "Number of moves can not be greater than 255" if moves > 255	

    data = file.read(72).unpack("C*")
    data.each do |elem|
        raise "Can't use unmatchable block in puzzles" if elem == 8
    end
    
    return PuzzleBuffer.new(moves, data)
end

def dump_puzzles(rom)
    file = File.open(rom, 'rb')

    file.seek(PUZZLE_OFFSETS)

    data = []

    NUM_PUZZLES.times do |i|
	    b1 = file.readbyte
	    b2 = file.readbyte
	    flippedoff = (b2 << 8 | b1)
	    #print "%d %04x\n" % [i, flippedoff & 0x1FFF]
	    #format of offset
	    #sssooooooooooooo
	    # s is the amount to shift by to get the first trio
	    # o is the offset from 0x48000
	    data << [i, flippedoff]
    end

    data.each do |arr|
	    index, loc = arr
	    preshift = (loc >> 12 & 0xE) / 2
	    #print "#{index} #{loc.to_s(16)} #{(loc&0x1FFF).to_s(16)} #{preshift}\n"
	    loc = loc & 0x1FFF

	    cursor = 0
	    row = 11
	    data = {}
	    data.default = 0
	
        file.seek(PUZZLE_OFFSETS + loc)
	    enum = file.each_byte

	    loop do
		    byte = enum.next
		    byte2 = enum.next
		    byte3 = enum.next
		    byte4 = enum.peek
		
		    num = byte | byte2 << 8 | byte3 << 16 | byte4 << 24
	        #p "%s %s" % [num.to_s(16), (num >> preshift).to_s(16)]
	        num = num >> preshift
	        
		    8.times do
		        bit = num & 0x7
		        #p bit
			    if bit == 7
				    cursor += 1 
				    row = 11
				    break if cursor >= 6
			    elsif bit != 0
				    raise "row is negative" if row < 0
				    data[[row, cursor]] = bit
				    row -= 1
			    else
			        raise "bit is 0"
			    end
			    num = num >> 3
			    break if num == 0
		    end
		    break if cursor >= 6
	    end
	
	    #print index.to_s + " : "
	    #print data.inspect
	    #print "\n\n"

	    file.seek(PUZZLE_MOVES_OFFSET + index)
	    moves = file.readbyte
	
	    write_puzzle(index, moves, data)
    end
end

def pack_puzzles(rom)
    buffer = CompressedPuzzleData.new
    offsets = []
    moves = []
    
    NUM_PUZZLES.times do |i|
        offsets << (buffer.offset + PUZZLE_DATA_OFFSET_START)
        
        pbuffer = read_puzzle(i)
        moves << pbuffer.moves
        column = 0
        row = 11
        while column < 6
            current = pbuffer.at(row, column)
            while current != 0
                buffer.add(current)
                row -= 1
                break if row < 0
                current = pbuffer.at(row, column)     
            end
            buffer.add(7)
            column += 1
            row = 11
        end
    end
    buffer.finish
    
    #buffer.buffer.each {|i| print "%02x," % i}
    #print "\n"
    #offsets.each {|i| print "%04x," % i}
    #print "\n"
    #p moves
    
    file = File.open(rom, 'rb+')
    file.seek(PUZZLE_MOVES_OFFSET)
    file.write(moves.pack('C*'))
    
    file.seek(PUZZLE_OFFSETS)
    file.write(offsets.pack('S*'))
    
    file.seek(PUZZLE_DATA)
    file.write(buffer.buffer.pack('C*'))
    
    file.close
end
 
if ARGV.size() != 2 or !%w(dump inject).include?(ARGV[1].downcase)
    raise "Usage: injector.rb rom_file command\ndump to dump puzzle data\ninject to inject puzzles into rom"
end



command = ARGV[1]

if command == 'dump'
    Dir.mkdir('ta') unless File.exists?('ta')
    dump_puzzles(ARGV[0])
    print "Puzzles dumped\n"
elsif command == 'inject'
    pack_puzzles(ARGV[0])
    print "Puzzles injected\n"
end
