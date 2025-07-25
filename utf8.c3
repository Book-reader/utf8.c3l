module utf8;
import std::io;

const UTF8_CHAR_SIZE = 4;
const UTF8_VECTOR_CHECK_SIZE = 8;

faultdef INVALID_CODEPOINT, NOT_SINGLE_CODEPOINT;

struct UTF8String (Printable) // could also be inline char[], but that would allow slicing which would break things. it still wouldn't allow autoconvert to String because it's also distinct and string has too many non-utf8 methods
{
	char[] buf;
}
fn String UTF8String.to_constant_string(&self) @dynamic => (String)self.buf;
fn String UTF8String.as_ascii(&self) => (String)self.buf;

typedef UTF8Char (Printable) = uint;
fn String UTF8Char.to_constant_string(&self) @dynamic => (String)bitcast(self, char[4]*);

fn UTF8String? String.as_utf8(self) @inline
{
	validate_utf8_string(self)!;
	return {self};
}

fn UTF8Char? String.as_utf8char(self) @inline
{
	if (validate_utf8_string(self)! != 1) return NOT_SINGLE_CODEPOINT?;
	return @string_to_utf8_char(self);
}

macro UTF8String @utf8(String $s) @builtin @const
{
	@validate_const_utf8_string($s);
	return {$s};
}

macro UTF8Char @utf8char(String $s) @builtin @const
{
	$if @validate_const_utf8_string($s) != 1:
		$error @sprintf("'%s' is not a single utf8 codepoint", $s);
	$endif
	// return (UTF8Char)bitorder::read((char[])$s, UIntLE);
	return @string_to_utf8_char($s);
}

<*
 @require @ok(validate_utf8_string(self.buf))
*>
fn usz UTF8String.len(&self) @operator(len) @inline => validate_utf8_string(self.buf)!!;

<*
 @require @ok(validate_utf8_string(self.buf))
 @require idx < self.len()
*>
fn UTF8Char UTF8String.get_char(&self, usz idx) @operator([])
{
	usz i, utf8i, char_size;
	// TODO: replace with char iterator that returns both char and byte idx
	do
	{
		char_size = utf8_char_len(self.buf[i..])!!;
		i += char_size;
	} while (utf8i != idx && ++utf8i);
	// char[4] buf;
	// buf[:char_size] = self.buf[i - char_size:char_size];
	return @string_to_utf8_char(self.buf[i - char_size:char_size]); // (UTF8Char)bitorder::read(buf, UIntLE);
}

<*
 @require @ok(validate_utf8_string(self.buf))
 @require idx < self.len()
*>
fn char[] UTF8String.get_char_slice(&self, usz idx)
{
/*	usz i, utf8i, char_size;
	// TODO: replace with char iterator that returns both char and byte idx
	do
	{
		char_size = utf8_char_len(self.buf[i..])!!;
		i += char_size;
	} while (utf8i != idx && ++utf8i);
	return self.buf[i - char_size:char_size];*/
	foreach (i, c : self.iter())
	{
		if (i == idx) return self.buf[c.byte_idx:c.char_size];
	}
	unreachable();
}

<*
 @require @ok(validate_utf8_string(self.buf))
 @require @ok(validate_utf8_string(other.buf))
*>
fn bool UTF8String.equals(&self, UTF8String other) @operator(==) @inline => self.buf == other.buf;

<*
// @ensure @ok(io::printfn("returned a slice of len %s containing '%s'", return.buf.len, return.buf))
 @require @ok(validate_utf8_string(self.buf))
 @require end_inc < self.len()
 @require start_inc <= end_inc
*>
fn UTF8String UTF8String.slice(&self, usz start_inc, usz end_inc)
{
	usz start_byte_idx, end_byte_idx;
	foreach (i, c : self.iter())
	{
		if (i == start_inc) start_byte_idx = c.byte_idx;
		if (i == end_inc)
		{
			end_byte_idx = c.byte_idx + c.char_size;
			break;
		}
	}
	return {self.buf[start_byte_idx..end_byte_idx - 1]};
}

<*
 @require @ok(validate_utf8_string(self.buf))
 @require start + len <= self.len()
*>
fn UTF8String UTF8String.slice_len(&self, usz start, usz len)
{
	usz i, utf8i, start_byte_idx, byte_len;
	// TODO: replace with iterator
	while (utf8i != start)
	{
		i += utf8_char_len(self.buf[i..])!!;
		utf8i++;
	}
	start_byte_idx = i;
	while (utf8i != start + len)
	{
		i += utf8_char_len(self.buf[i..])!!;
		utf8i++;
	}
	byte_len = i - start_byte_idx;
	return {self.buf[start_byte_idx:byte_len]};
}

fn char[] UTF8String.bytes(&self) @inline => self.buf;

// a more efficient way of iterating over a utf8 string than foreach (c : self) in linear time instead of in whatever time it usually is (too much time)
<*
  @require @ok(validate_utf8_string(self.buf))
*>
fn UTF8Iterator UTF8String.iter(self) => {.string = self};

<*
  @require @ok(validate_utf8_string(self.buf))
*>
fn UTF8CharIterator UTF8String.iter_chars(self) => {.string = self};

<*
 @require @ok(validate_utf8_string(self.buf))
 @require @ok(validate_utf8_char(c))
*>
fn usz? UTF8String.index_of_char(&self, UTF8Char c)
{
	foreach (i, c1 : self.iter_chars()) if (c == c1) return i;
	return NOT_FOUND?;
}

fn bool UTF8String.contains_char(&self, UTF8Char c) => @ok(self.index_of_char(c));

<*
 @require @ok(validate_utf8_string(self.buf))
 @require @ok(validate_utf8_string(needle.buf))
*>
fn usz? UTF8String.index_of(&self, UTF8String needle)
{
	if (self.buf.len == 0 || needle.buf.len == 0) return NOT_FOUND?;
	usz needle_len = needle.len();
	isz self_len = self.len();
	if (self_len < needle_len) return NOT_FOUND?;

	for (usz i = 0; i < self_len; i++)
	{
		if (i + needle_len > self_len) return NOT_FOUND?;
		if (self.slice_len(i, needle_len) == needle) return i;
	}
	return NOT_FOUND?;
}

fn bool UTF8String.contains(&self, UTF8String needle) => @ok(self.index_of(needle));


struct UTF8Iterator
{
	UTF8String string;
	usz char_idx;
	usz byte_idx;
}

struct UTF8IteratorValue
{
	usz byte_idx;
	UTF8Char val;
	char char_size;
}

<*
 @require idx == self.char_idx : "Must do a foreach loop over UTF8Iterator"
*>
fn UTF8IteratorValue UTF8Iterator.get(&self, usz idx) @operator([]) @inline
{
	char char_size = utf8_char_len(self.string.buf[self.byte_idx..])!!;
	defer
	{
		self.char_idx ++;
		self.byte_idx += char_size;
	}
	return {self.byte_idx, @string_to_utf8_char(self.string.buf[self.byte_idx:char_size]), char_size};
}

typedef UTF8CharIterator = inline UTF8Iterator;

<*
 @require idx == self.char_idx : "Must do a foreach loop over UTF8CharIterator"
*>
fn UTF8Char UTF8CharIterator.get(&self, usz idx) @operator([]) @inline => ((UTF8Iterator*)self).get(idx) @inline.val;

fn usz UTF8Iterator.len(&self) @operator(len) @inline => self.string.len();
fn usz UTF8CharIterator.len(&self) @operator(len) @inline => self.string.len();

module utf8 @private;

bitstruct UTF8CharBuilder : UTF8Char @littleendian
{
	char one : 0..7;
	char two : 8..15;
	char three : 16..23;
	char four : 24..31;
}

macro UTF8Char @string_to_utf8_char(char[] #s) => (UTF8Char)(UTF8CharBuilder)
{
	.one   = #s.len > 0 ? #s[0] : 0,
	.two   = #s.len > 1 ? #s[1] : 0,
	.three = #s.len > 2 ? #s[2] : 0,
	.four  = #s.len > 3 ? #s[3] : 0,
};

import std::io;
macro usz? validate_utf8_string(char[] s)
{
	// io::printfn("validating string for the %s time", a++);
	usz len;
	for (usz byte_len; byte_len < s.len; byte_len += utf8_char_len(s[byte_len..])!, len++);
	return len;
}

const MAX_CONST_UTF8_VALIDATE = 50_000;
macro usz @validate_const_utf8_string($s) @const
{
	$if $s.len > MAX_CONST_UTF8_VALIDATE:
		$echo @sprintf("(%s:%s) Warning: not validating constant utf8 string with size %s as it is too long", $$FILEPATH, $$LINE, $s.len);
		return 0;
	$else
		usz $len = 0;
		$for var $i = 0; $i < $s.len;:
			var $check_len = @select($s.len - $i > UTF8_CHAR_SIZE, UTF8_CHAR_SIZE, $s.len - $i);
			char[*] $chars = $s[$i:$check_len];
			$i += @utf8_char_len($chars);
			$len ++;
		$endfor
		return $len;
	$endif
}

macro char? validate_utf8_char(UTF8Char c) => utf8_char_len(c.to_constant_string());

<*
	@require self.len > 0
*>
macro char? utf8_char_len(char[] self) {
	// if (self.len == 8 && (char[<UTF8_VECTOR_CHECK_SIZE>])self[:UTF8_VECTOR_CHECK_SIZE] & 0x80 == (char[<UTF8_VECTOR_CHECK_SIZE>]){[0..7] = 0}) return UTF8_VECTOR_CHECK_SIZE;
	switch (self[0])
	{
		// one byte
		case 0..0x7F:
			return 1;
		// two byte
		case 0xC2..0xDF:
			if (@likely(self.len > 1 && self[1].is_utf8_tail())) return 2;
			return INVALID_CODEPOINT?;
		// three byte
		case 0xE0:
			if (@likely(self.len > 2 &&
				self[1] & 0b11100000 == 0b10100000 &&
				self[2].is_utf8_tail())) return 3;
			return INVALID_CODEPOINT?;
		// three byte
		case 0xE1..0xEC:
		case 0xEE..0xEF:
			if (@likely(self.len > 2 &&
				self[1].is_utf8_tail() &&
				self[2].is_utf8_tail())) return 3;
			return INVALID_CODEPOINT?;
		// three byte
		case 0xED:
			if (@likely(self.len > 2 &&
				self[1] & 0b11100000 == 0b10000000 &&
				self[2].is_utf8_tail())) return 3;
			return INVALID_CODEPOINT?;
		// four byte
		case 0xF0:
			if (@likely(self.len > 3 &&
				(self[1] >= 0x90 && self[1] <= 0xBF) &&
				self[2].is_utf8_tail() &&
				self[3].is_utf8_tail())) return 4;
			return INVALID_CODEPOINT?;
		// four byte
		case 0xF1..0xF3:
			if (@likely(self.len > 3 &&
				self[1].is_utf8_tail() &&
				self[2].is_utf8_tail() &&
				self[3].is_utf8_tail())) return 4;
			return INVALID_CODEPOINT?;
		// four byte
		case 0xF4:
			if (@likely(self.len > 3 &&
				self[1] & 0b11110000 == 0b100000 &&
				self[2].is_utf8_tail() &&
				self[3].is_utf8_tail())) return 4;
			return INVALID_CODEPOINT?;
		default:
			return INVALID_CODEPOINT?;
	}
}

macro char @utf8_char_len(char[*] $self) @const
{
	bool $done = false;
	$switch $self[0]:
		// one byte
		$case 0..0x7F:
			$done = true;
			return 1;
		// two byte
		$case 0xC2..0xDF:
			$if ($self.len > 1 && $self[1].is_utf8_tail()): $done = true; return 2; $endif
		// three byte
		$case 0xE0:
			$if $self.len > 2 &&
				$self[1] & 0b11100000 == 0b10100000 &&
				$self[2].is_utf8_tail(): $done = true; return 3; $endif
		// three byte
		$case 0xE1..0xEC:
		$case 0xEE..0xEF:
			$if $self.len > 2 &&
				$self[1].is_utf8_tail() &&
				$self[2].is_utf8_tail(): $done = true; return 3; $endif
		// three byte
		$case 0xED:
			$if $self.len > 2 &&
				$self[1] & 0b11100000 == 0b10000000 &&
				$self[2].is_utf8_tail(): $done = true; return 3; $endif
		// four byte
		$case 0xF0:
			$if $self.len > 3 &&
				($self[1] >= 0x90 && $self[1] <= 0xBF) &&
				$self[2].is_utf8_tail() &&
				$self[3].is_utf8_tail(): $done = true; return 4; $endif
		// four byte
		$case 0xF1..0xF3:
			$if $self.len > 3 &&
				$self[1].is_utf8_tail() &&
				$self[2].is_utf8_tail() &&
				$self[3].is_utf8_tail(): $done = true; return 4; $endif
		// four byte
		$case 0xF4:
			$if $self.len > 3 &&
				$self[1] & 0b11110000 == 0b100000 &&
				$self[2].is_utf8_tail() &&
				$self[3].is_utf8_tail(): $done = true; return 4; $endif
		$default:
	$endswitch
	$if $done == false: $error "Invalid utf-8 codepoint"; $endif
}


macro bool char.is_utf8_tail(#self) @safemacro => (#self) & 0b11000000 == 0b10000000;

