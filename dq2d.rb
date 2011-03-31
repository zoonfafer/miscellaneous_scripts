#!/usr/bin/env ruby
# 
# Converts from dotted quad notation to decimal.
# ... and vice versa.
#
# TODO: make it accept input from stdin.
#
# Jeffrey Lau
# Fri Jan 16 21:52:14 GMT 2009

$N = File.basename( $0 )
$VERSION = 0.01

# Dotted Quad to Decimal
def dq2d( dq )
	ary = dq.split( "." )
	if ary.length > 4 || ary.length < 2
		# has to be a quad
		warn sprintf( "Error:- I don't know how to parse `%s'.", dq )
		return
	end
	# our decimal result
	return ary.
		collect{|q| q.to_i }. # make integers
		# Wow!  This is my first time to use
		# `instance_eval' just so I can continue
		# the method invocation chain.  How neat!
		instance_eval{|ary|
			# [ ary[0], ary[1], ary[2], ary[-1] ]
			[ 0, 1, 2, -1 ].
			collect{|n| ( ary.length - n <= 1 ) ? 0 : ary[n] } # differentiate between the last element and the middle ones
		}. # fit into 4 quads
		inject( 0 ){|res,q| res <<= 8; res += q } # actual calculation
end

# Decimal to Dotted Quad
def d2dq( dec )
	d = dec.to_i # whatever...
	# warn if number is bigger than 255.255.255.255
	if d >> 32 > 0 then
		warn sprintf(
			"Warning: the number `%d' maybe rather too big. (%d too big.)",
			d,
			d - (( 1 << 32 ) - 1 )
		)
	end
	bytemask = (( 1 << 8 ) - 1 ) # it looks like `11111111' in binary.

	# our dotted quad result
	return (0..3).
		to_a.
		reverse. # #=> [ 3, 2, 1, 0 ]
		collect{|n| ( d >> 8 * n ) & bytemask }. # actual calculation
		join( "." )
end

def show_usage
	puts "Usage:  #{$N} <dotted_quad_address1> [<dotted_quad_address2> ...]"
	puts "        #{$N} -i|--inverse <decimal_address1> [<decimal_address2> ...]"
	puts "  No other help is available."
end

def err_usage
	show_usage
	exit 1
end

if __FILE__ == $0 then
	if ARGV.empty? then
		err_usage
	else
		if ARGV[0] == "-i" || ARGV[0] == "--inverse" then
			ARGV.shift
			if ARGV.empty? then
				err_usage
			else
				ARGV.each do |d|
					dotted_quad = d2dq( d )
					puts dotted_quad unless dotted_quad.nil?
				end
			end
		else
			ARGV.each do |dq|
				decimal = dq2d( dq )
				puts decimal unless decimal.nil?
			end
		end
	end
end
__END__
