---
title:  "MetalClaw"
author: Gary Talent
description: "An Efficient Serialization Format"
categories: ["Tech", "Programming"]
images:
- /dt-logo.png
tags: ["cpp", "low memory", "programming", "serialization", "metal claw", "nostalgia"]
date: 2022-06-25
showtoc: true
---

## Synopsis

In *Nostalgia*, stored representations of data tend to take the form of one to
one mappings to serialized data structures.
*Nostalgia* uses this approach for game saves, creature definitions, world
layout, and a good deal more.
Representing this data in JSON allows for easy debugging, as it is a human
readable data serialization format, however that convenience comes at a cost to
performance and size.
This cost is negligible on modern PCs, but it is completely unsuitable for such
limited hardware as the GBA.

A more efficient serialization format is needed, hence MetalClaw.
MetalClaw is a more compact alternative to JSON planned for use in the GBA
version of *Nostalgia*.

This document focuses on the MetalClaw format itself, not the implementation or
API.

Note: This document actually details the second version of MetalClaw, and not
the first.
The first version is no longer relevant.

## Requirements and Assumptions
In designing MetalClaw, we will assume that values have no null or undefined
state, but they do have default values that they receive if the serialized
representation provides none.

Default values:

* String: ""
* Integers: 0
* Bool: false
* Arrays and maps: empty

## Primitive Types

### Integers
JSON's representation of integers is readable, but wasteful.
Say that we want to serialize the number 25.
We should need only 1 byte to represent 25, but it uses 2 bytes in JSON.
To address this, it is helpful represent the integer in binary instead of plain
text.
Unfortunately, this can actually prove even more wasteful in some cases.
Say you have a 32 bit integer with a value of 25.
The 2 byte plain text representation of 25 would inflate to 4 bytes.
This works out well for numbers greater than 9,999, but if a large portion of
the numbers represented fall below 1,000, then it will generally cost more
space than it saves.

Another reason for wanting variable length integers has to do with the API.
As stated earlier, the API will generally not be discussed here, but this is an
area where the API foists a requirement on the format itself.
The API does not necessarily want to foist this requirement on the format, but
C++ makes it rather hard not to.
The language standard does not guarantee the size of the integer types.
C++ has types that vary in size between compilers and processor architectures.
Many times developers use long on one platform where it is 64 bit, but it will
be 32 bit on another.
While developers *should* simply use int{8,16,32,64}_t these days, that should not be
assumed.
Such an assumption will result in the wrong size type being used to read data
written by a build from a different compiler or target architecture.
Integers should not inherit the size of the input type.

To implement variable length integers, we will take a page from the design of
UTF-8: continuation bytes.

Starting with the least significant bit of the first byte, we look for the
first 0 in the first byte in the integer, and for every 1 found before that,
there will be one additional continuation byte.
0001'1001 has no continuation bytes, whereas 0011'0010 has 1 continuation byte
after it, and so on.

Integers within the -64 to 63 range will be 8 bits, outside that range they
will move on to 16, 24, 32, or 64 bits as needed.

Do give some extra thought to negative numbers though.
The sign indicator, being the most significant bit, will need to moved.
Also, consider how two's compliment binary works.
In negative two's complement, values closer to zero use higher significance
bits in field.
An 8 bit two's compliment integer with the value of 1111'1111 has a value of -1.
A 16 bit two's compliment integer with the value of 1111'1111'1111'1111 also has
a value of -1.
A -1 stored in an int64 would require the full 8 data bytes, plus a full 9th
byte for tracking the continuation bytes.
There really is no need for these extra bits to achieve that value though, so
MetalClaw truncates unnecessary bits from negative values where possible.

Below you will find example encodings for both signed and unsigned integers.
Note the rather oddly placed pipe symbol at the end of each encoding, it
represents the continuation bit indicator section.

Signed encoding:
```cpp
   1 =>           0b000'0001|0
   2 =>           0b000'0010|0
   3 =>           0b000'0011|0
   4 =>           0b000'0100|0
  64 => 0b00'0000'0100'0000|01
 128 => 0b00'0000'1000'0000|01
 129 => 0b00'0000'1000'0001|01
 130 => 0b00'0000'1000'0010|01
 131 => 0b00'0000'1000'0011|01
  -1 =>           0b111'1111|0
  -2 =>           0b111'1110|0
  -3 =>           0b111'1101|0
  -4 =>           0b111'1100|0
 -64 =>           0b100'0000|0
-128 => 0b11'1111'1000'0000|01
-129 => 0b11'1111'0111'1111|01
-130 => 0b11'1111'0111'1110|01
-131 => 0b11'1111'0111'1101|01
```

Unsigned encoding:
```cpp
  1 =>           0b000'0001|0
  2 =>           0b000'0010|0
  3 =>           0b000'0011|0
  4 =>           0b000'0100|0
 64 =>           0b100'0000|0
128 => 0b00'0000'1000'0000|01
129 => 0b00'0000'1000'0001|01
130 => 0b00'0000'1000'0010|01
131 => 0b00'0000'1000'0011|01
```

We will use the use the following notation to denote a variable length integer
stored in binary, (25). [25] will represent a fixed length binary integer.

### Strings
For the sake of getting the string size at the outset of reading, MetalClaw
will place the size at the beginning of each string.
Strings will not have a null terminator.

Example:
```python
(8)A string
```

## Complex Primitives

### Field Names and Field Presence Maps
Before we jump into the complex types, we need to address a basic building
block of complex primitives.

One of the biggest sources of bloat inherit to JSON is found in the field
labels in objects.
Field names make for a readable and robust format, but more efficient ways of
differentiating fields in a serialization format exist if we already know the
field names.
Another method is defining a set order in which each field will appear in the
serialized representation of the data, but that would require us to list every
field even if they have the default values.
Eliminating the field names alone will often inflate the size of the data, but
this is an important stepping stone in reducing the size of the data.

To replace the functionality of JSON's bloated field names, we use a field
presence map.

The field presence map is a series of bytes that assigns each field a bit.
There are enough bytes in each field presence maps to handle all fields.
The first field will map to the least significant bit of the first byte, the
second field will map to the second bit, etc.
If there is a ninth field, it will use the first bit of the second byte.

With a field presence map, we can omit the default values.
The map to describe our example data below will be the following in binary,
1110'0000, or 224 in decimal.

The presence map exhibits a strange property with bools.
You may have noticed that bools were missing from the previous from the
primitives section.
Bools only have 2 possible values, just as each bit in the presence map, so the
presence bit can actually contain the data of the bool, thus making the value
section of a bool redundant.

### Structs

We will use this type as an example of what we are serializing:
```c++
struct S {
	int        field1;
	ox::String field2;
	bool       field3;
	bool       field4;
	bool       field5;
	bool       field6;
	bool       field7;
	bool       field8;
};
```

```json
{"field1": 25, "field2": "A string", "field3": true}
```

```python
[224](25)(8)A string
```

### Unions

As in C, unions are similar to structs.
Unions are structs that allow only a single field to be set.
Unions continue to use the field presence map to express which field is set.

### Lists

Lists are essentially objects with a length field at the front.

Because the format does not bundle field names with the data, the nth value of
a MetalClaw object can map to the nth value of an array just the same as a
field in a struct.

The length field is a variable length integer and the presence map will have
enough bytes to support the array length specified in the length field.

Let's serialize the following data:
```c++
struct S {
	ox::Vector<int> list;
};
```

```json
{
	"list": [0, 1, 2, 3]
}
```

The resulting MetalClaw would be:

```python
[128](4)[112](1)(2)(3)
```

### Maps

Maps are essentially lists that go back to using field keys instead of field
presences maps.
Value identifiers immediately precede their values.

For our map example we will us the following:
```c++
struct S {
	ox::HashMap<ox::String, int> list;
};
```

```json
{
	"list": {
		"field1": 0,
		"field2": 1,
		"field3": 2,
		"field4": 3
	}
}
```

The resulting MetalClaw would be:

```python
[128](4)(6)field1(0)(6)field2(1)(6)field3(2)(6)field4(3)
```

## Final Format
Below is a loose BNF spec for MetalClaw:

```
       <value> ::= <object>|<primitive>|<list>|<map>
      <length> ::= <variable-length-int>
      <fields> ::= <value><fields>|<value>
      <object> ::= <presence-map><fields>
      <length> ::= <fixed-length-int>
<presence-map> ::= uint8_t[fieldCount / 8]
        <list> ::= <length><object>
         <map> ::= <length><pairs>
       <pairs> ::= <field><pairs>|<pair>
        <pair> ::= <key><value>
         <key> ::= <value>
   <primitive> ::= <string>|<var-len-int>
      <string> ::= <var-len-int>raw string data
 <var-len-int> ::= byte<var-len-int>|byte
```

