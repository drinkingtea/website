---
title:  "Nostalgia Developer Handbook"
author: Gary Talent
description: "Standards and conventions of Nostalgia"
categories: ["Tech", "Programming"]
tags: ["c++", "programming", "serialization", "reflection", "ox", "nostalgia"]
date: 2022-02-23
showtoc: true
---

Note: this document is a copy of a document in the [Nostalgia
repo](https://git.drinkingtea.net/drinkingtea/nostalgia) and will periodically
be updated.

Last updated: 2024-05-29

# Nostalgia Developer Handbook

## About

The purpose of the Developer Handbook is similar to that of the README.
The README should be viewed as a prerequisite to the Developer Handbook.
The README should provide information needed to build the project, which might
be used by an advanced user or a person trying to build and package the
project.
The Developer Handbook should focus on information needed by a developer
working on the project.

## Project Structure

### Overview

All components have a platform indicator next to them:

    (PG) - PC, GBA
    (-G) - GBA
    (P-) - PC

* Nostalgia
  * modules
    * core - graphics system for Nostalgia (PG)
      * gba - GBA implementation (PG)
      * opengl - OpenGL implementation (P-)
      * studio - studio plugin for core (P-)
      * keel - keel plugin for core (PG)
    * scene - defines & processes map data (PG)
      * studio - studio plugin for scene (P-)
      * keel - keel plugin for scene (PG)
  * player - plays the games (PG)
  * studio - makes the games (P-)
  * tools - command line tools (P-)
    * pack - packs a studio project directory into an OxFS file (P-)
* Olympic
    * Applib - Library for creating apps as libraries that injects Keel and Studio modules
    * Keel - asset management system (PG)
    * Studio - where most of the studio code lives as library (P-)
        * applib - used for per project studio executables
        * modlib - used for studio modules to interact with studio
    * Turbine - platform abstraction and user I/O (PG)
        * gba - GBA implementation (PG)
        * glfw - GLFW implementation (P-)
* deps - project dependencies
  * Ox - Library of things useful for portable bare metal and userland code. Not really that external...
    * clargs - Command Line Args processing (PG)
    * claw - Reads and writes Metal or Organic Claw with header to indicate which
    * event - Qt-like signal system
    * fs - file system (PG)
	 * logconn - connects logging to Bullock (P-)
    * mc - Metal Claw serialization, builds on model (PG)
    * oc - Organic Claw serialization (wrapper around JsonCpp), builds on model (P-)
    * model - Data structure modelling (PG)
	 * preloader - library for handling preloading of data (PG)
    * std - Standard-ish Library with a lot missing and some things added (PG)
  * GlUtils - OpenGL helpers (P-)
  * teagba - GBA assembly startup code (mostly pulled from devkitPro under MPL
	          2.0), and custom GBA hardware interop code (-G)

## Platform Notes

### GBA

The GBA has two major resources for learning about its hardware:

* [Tonc](https://www.coranac.com/tonc/text/toc.htm) - This is basically a short
  book on the GBA and low level development.
* [GBATEK](https://rust-console.github.io/gbatek-gbaonly/) - This is a more
  concise resource that mostly tells about memory ranges and registers.

#### Graphics

* Background Palette: 256 colors
* Sprite Palette:     256 colors

## Code Base Conventions

### Formatting

* Indentation is done with tabs.
* Alignment is done with spaces.
* Opening brackets go on the same line as the thing they are opening for (if,
  while, for, try, catch, function, etc.)
* No space between function parentheses and arguments.
* Spaces between arithmetic/bitwise/logical/assignment operands and operators.
* Pointer and reference designators should be bound to the identifier name and
  not the type, unless there is not identifier name, in which case it should be
  bound to the type.

### Write C++, Not C

On the surface, it seems like C++ changes the way we do things from C for no
reason, but there are reasons for many of these duplications of functionality.
The C++ language designers aren't stupid. Question them, but don't ignore them.

#### Casting

Do not use C-style casts.
C++ casts are more readable, and more explicit about the type of cast being
used.
Do not use ```dynamic_cast``` in code building for the GBA, as RTTI is disabled
in GBA builds.

#### Library Usage

C++ libraries should generally be preferred to C libraries.
C libraries are allowed, but pay extra attention.

This example from nostalgia::core demonstrates the type of problems that can
arise from idiomatically mixed code.

```cpp
uint8_t *loadRom(const char *path) {
	auto file = fopen(path, "r");
	if (file) {
		fseek(file, 0, SEEK_END);
		const auto size = ftell(file);
		rewind(file);
		// new can technically throw, though this project considers out-of-memory
		// to be unrecoverable
		auto buff = new uint8_t[size];
		fread(buff, size, 1, file);
		fclose(file);
		return buff;
	} else {
		return nullptr;
	}
}
```

In practice, that particular example is not something we really care about
here, but it does demonstrate that problems can arise when mixing what might be
perceived as cool old-school C-style code with lame seemingly over-complicated
C++-style code.

Here is another more concrete example observed in another project:
```cpp
int main() {
	// using malloc does not call the constructor
	std::vector<int> *list = (std::vector<int>*) malloc(sizeof(std::vector<int>));
	doStuff(list);
	// free does not call the destructor, which causes memory leak for array
	// inside list
	free(list);
	return 0;
}
```

The code base where this was observed actually got away with this for the most
part, as the std::vector implementation used evidently waited until the
internal array was needed before initializing and the memory was zeroed out
because the allocation occurred early in the program's execution.
While the std::vector implementation in question worked with this code and the
memory leak is not noticeable because the std::vector was meant to exist for
the entire life of the process, other classes likely will not get away with it
due to more substantial constructors and more frequent instantiations of the
classes in question.

## Project Systems

### Error Handling

The GBA build has exceptions disabled.
Instead of throwing exceptions, all engine code must return ```ox::Error```s.
For the sake of consistency, try to stick to ```ox::Error``` in non-engine code
as well, but non-engine code is free to use exceptions when they make sense.
Nostalgia and Ox both use ```ox::Error``` to report errors. ```ox::Error``` is
a struct that has overloaded operators to behave like an integer error code,
plus some extra fields to enhance debuggability.
If instantiated through the ```OxError(x)``` macro, it will also include the
file and line of the error.
The ```OxError(x)``` macro should only be used for the initial instantiation of
an ```ox::Error```.

In addition to ```ox::Error``` there is also the template ```ox::Result<T>```.
```ox::Result``` simply wraps the type T value in a struct that also includes
error information, which allows the returning of a value and an error without
resorting to output parameters.

If a function returns an ```ox::Error``` or ```ox::Result``` it should be
declared as ```noexcept``` and all exceptions should be translated to an
```ox::Error```.

```ox::Result``` can be used as follows:

```cpp
ox::Result<int> foo(int i) noexcept {
	if (i < 10) {
		return i + 1; // implicitly calls ox::Result<T>::Result(T)
	}
	return OxError(1); // implicitly calls ox::Result<T>::Result(ox::Error)
}

int caller1() {
	auto v = foo(argc);
	if (v.error) {
		return 1;
	}
	std::cout << v.value << '\n';
	return 0;
}

int caller2() {
	// it is also possible to capture the value and error in their own variables
	auto [val, err] = foo(argc);
	if (err) {
		return 1;
	}
	std::cout << val << '\n';
	return 0;
}

ox::Error caller3(int &i) {
    return foo(i).moveTo(i);
}

ox::Error caller4(int &i) {
    return foo(i).copyTo(i);
}

int caller5(int i) {
    return foo(i).unwrap(); // unwrap will kill the program if there is an error
}

int caller6(int i) {
    return foo(i).unwrapThrow(); // unwrap will throw if there is an error
}

int caller7(int i) {
    return foo(i).or_value(0); // will return 0 if foo returned an error
}

ox::Result<uint64_t> caller8(int i) {
    return foo(i).to<uint64_t>(); // will convert the result of foo to uint64_t
}
```

Lastly, there are a few macros available to help in passing ```ox::Error```s
back up the call stack, ```oxReturnError```, ```oxThrowError```, and
```oxRequire```.

```oxReturnError``` is by far the more helpful of the two.
```oxReturnError``` will return an ```ox::Error``` if it is not 0 and
```oxThrowError``` will throw an ```ox::Error``` if it is not 0.
Because exceptions are disabled for GBA builds and thus cannot be used in the
engine, ```oxThrowError``` is  only really useful at the boundary between
engine libraries and Nostalgia Studio.

Since ```ox::Error``` is always nodiscard, you must do something with them.
In rare cases, you may not have anything you can do with them or you may know
the code will never fail in that particular instance.
This should be used sparingly.


```cpp
void studioCode() {
	auto [val, err] = foo(1);
	oxThrowError(err);
	doStuff(val);
}

ox::Error engineCode() noexcept {
	auto [val, err] = foo(1);
	oxReturnError(err);
	doStuff(val);
	return OxError(0);
}

void anyCode() {
    auto [val, err] = foo(1);
    std::ignore = err;
    doStuff(val);
}
```

Both macros will also take the ```ox::Result``` directly:

```cpp
void studioCode() {
	auto valerr = foo(1);
	oxThrowError(valerr);
	doStuff(valerr.value);
}

ox::Error engineCode() noexcept {
	auto valerr = foo(1);
	oxReturnError(valerr);
	doStuff(valerr.value);
	return OxError(0);
}
```

Ox also has the ```oxRequire``` macro, which will initialize a value if there is no error, and return if there is.
It aims to somewhat emulate the ```?``` operator in Rust and Swift.

Rust ```?``` operator:
```rust
fn f() -> Result<i32, i32> {
  // do stuff
}

fn f2() -> Result<i32, i32> {
  let i = f()?;
  Ok(i + 4)
}
```

```oxRequire```:
```cpp
ox::Result<int> f() noexcept {
	// do stuff
}

ox::Result<int> f2() noexcept {
	oxRequire(i, f()); // const auto [out, oxConcat(oxRequire_err_, __LINE__)] = x; oxReturnError(oxConcat(oxRequire_err_, __LINE__))
	return i + 4;
}
```
```oxRequire``` is not quite as versatile, but it should still cleanup a lot of otherwise less ideal code.

```oxRequire``` also has variants for throwing the error and for making to value non-const:

* ```oxRequireM``` - oxRequire Mutable
* ```oxRequireT``` - oxRequire Throw
* ```oxRequireMT``` - oxRequire Mutable Throw

The throw variants of ```oxRequire``` are generally legacy code.
```ox::Result::unwrapThrow``` is generally preferred now.

### Logging and Output

Ox provides for logging and debug prints via the ```oxTrace```, ```oxDebug```, and ```oxError``` macros.
Each of these also provides a format variation.

Ox also provide ```oxOut``` and ```oxErr``` for printing to stdout and stderr.
These are intended for permanent messages and always go to stdout and stderr.

Tracing functions do not go to stdout unless the OXTRACE environment variable is set.
They also print with the channel that they are on, along with file and line.

Debug statements go to stdout and go to the logger on the "debug" channel.
Where trace statements are intended to be written with thoughtfulness,
debug statements are intended to be quick and temporary insertions.
Debug statements trigger compilation failures if OX_NODEBUG is enabled when CMake is run,
as it is on Jenkins builds, so ```oxDebug``` statements should never be checked in.
This makes ```oxDebug``` preferable to other forms of logging, as temporary prints should
never be checked in.

```oxError``` always prints.
It includes file and line, and is prefixed with a red "ERROR:".
It should generally be used conservatively.
It shuld be used only when there is an error that is not technically fatal, but
the user almost certainly wants to know about it.

```oxTrace``` and ```oxTracef```:
```cpp
void f(int x, int y) { // x = 9, y = 4
	oxTrace("nostalgia::core::sdl::gfx") << "f:" << x << y; // Output: "f: 9 4"
	oxTracef("nostalgia::core::sdl::gfx", "f: {}, {}", x, y); // Output: "f: 9, 4"
}
```

```oxDebug``` and ```oxDebugf```:
```cpp
void f(int x, int y) { // x = 9, y = 4
	oxDebug() << "f:" << x << y; // Output: "f: 9 4"
	oxDebugf("f: {}, {}", x, y); // Output: "f: 9, 4"
}
```

```oxError``` and ```oxErrorf```:
```cpp
void f(int x, int y) { // x = 9, y = 4
	oxError() << "f:" << x << y; // Output: "ERROR: (<file>:<line>): f: 9 4"
	oxErrorf("f: {}, {}", x, y); // Output: "ERROR: (<file>:<line>): f: 9, 4"
}
```

### File I/O

All engine file I/O should go through nostalgia::core::Context, which should go
through ox::FileSystem. Similarly, all studio file I/O should go thorough
nostalgia::studio::Project, which should go through ox::FileSystem.

ox::FileSystem abstracts away differences between conventional storage devices
and ROM.

### Model System

Ox has a model system that provides a sort of manual reflection mechanism.

Models require a model function for the type that you want to model.
It is also good to provide a type name and type version number, though that is not required.

The model function takes an instance of the type it is modelling and a template
parameter type.
The template parameter type must implement the API used in the models, but it
can do anything with the data provided to it.

Here is an example from the Nostalgia/Core package:

```cpp
struct NostalgiaPalette {
	static constexpr auto TypeName = "net.drinkingtea.nostalgia.core.NostalgiaPalette";
	static constexpr auto TypeVersion = 1;
	ox::Vector<Color16> colors;
};

struct NostalgiaGraphic {
	static constexpr auto TypeName = "net.drinkingtea.nostalgia.core.NostalgiaGraphic";
	static constexpr auto TypeVersion = 1;
	int8_t bpp = 0;
	// rows and columns are really only used by TileSheetEditor
	int rows = 1;
	int columns = 1;
	ox::FileAddress defaultPalette;
	NostalgiaPalette pal;
	ox::Vector<uint8_t> pixels;
};

template<typename T>
constexpr ox::Error model(T *h, ox::CommonPtrWith<NostalgiaPalette> auto *pal) noexcept {
	h->template setTypeInfo<NostalgiaPalette>();
	// it is also possible to provide the type name and type version as function arguments
	//h->setTypeInfo("net.drinkingtea.nostalgia.core.NostalgiaPalette", 1);
	oxReturnError(h->field("colors", &pal->colors));
	return OxError(0);
}

template<typename T>
constexpr ox::Error model(T *h, ox::CommonPtrWith<NostalgiaGraphic> auto *ng) noexcept {
	h->template setTypeInfo<NostalgiaGraphic>();
	oxReturnError(h->field("bpp", &ng->bpp));
	oxReturnError(h->field("rows", &ng->rows));
	oxReturnError(h->field("columns", &ng->columns));
	oxReturnError(h->field("defaultPalette", &ng->defaultPalette));
	oxReturnError(h->field("pal", &ng->pal));
	oxReturnError(h->field("pixels", &ng->pixels));
	return OxError(0);
}
```

The model system also provides for unions:

```cpp

#include <ox/model/types.hpp>

class FileAddress {

	template<typename T>
	friend constexpr Error model(T*, ox::CommonPtrWith<FileAddress> auto*) noexcept;

	public:
		static constexpr auto TypeName = "net.drinkingtea.ox.FileAddress";

		union Data {
			static constexpr auto TypeName = "net.drinkingtea.ox.FileAddress.Data";
			char *path;
			const char *constPath;
			uint64_t inode;
		};

	protected:
		FileAddressType m_type = FileAddressType::None;
		Data m_data;

};

template<typename T>
constexpr Error model(T *h, ox::CommonPtrWith<FileAddress::Data> auto *obj) noexcept {
	h->template setTypeInfo<FileAddress::Data>();
	oxReturnError(h->fieldCString("path", &obj->path));
	oxReturnError(h->fieldCString("constPath", &obj->path));
	oxReturnError(h->field("inode", &obj->inode));
	return OxError(0);
}

template<typename T>
constexpr Error model(T *io, ox::CommonPtrWith<FileAddress> auto *fa) noexcept {
	io->template setTypeInfo<FileAddress>();
	// cannot read from object in Reflect operation
	if constexpr(ox_strcmp(T::opType(), OpType::Reflect) == 0) {
		int8_t type = 0;
		oxReturnError(io->field("type", &type));
		oxReturnError(io->field("data", UnionView(&fa->m_data, 0)));
	} else {
		auto type = static_cast<int8_t>(fa->m_type);
		oxReturnError(io->field("type", &type));
		fa->m_type = static_cast<FileAddressType>(type);
		oxReturnError(io->field("data", UnionView(&fa->m_data, static_cast<int>(fa->m_type))));
	}
	return OxError(0);
}

```

There are also macros in ```<ox/model/def.hpp>``` for simplifying the declaration of models:

```cpp
oxModelBegin(NostalgiaGraphic)
	oxModelField(bpp)
	oxModelField(rows)
	oxModelField(columns)
	oxModelField(defaultPalette)
	oxModelField(pal)
	oxModelField(pixels)
oxModelEnd()
```

### Serialization

Using the model system, Ox provides for serialization.
Ox has MetalClaw and OrganicClaw as its serialization format options.
MetalClaw is a custom binary format designed for minimal size.
OrganicClaw is a wrapper around JsonCpp, chosen because it technically
implements a superset of JSON.
OrganicClaw requires support for 64 bit integers, whereas normal JSON
technically does not.

These formats do not currently support floats.

There is also a wrapper format called Claw that provides a header at the
beginning of the file and can dynamically switch between the two depending on
what the header says is present.
The Claw header also includes information about the type and type version of
the data.

Claw header: ```M1;net.drinkingtea.nostalgia.core.NostalgiaPalette;1;```

That reads:

* Format is Metal Claw, version 1
* Type ID is net.drinkingtea.nostalgia.core.NostalgiaPalette
* Type version is 1

Except when the data is exported for loading on the GBA, Claw is always used as
a wrapper around the bare formats.

#### Metal Claw Example

##### Read

```cpp
#include <ox/mc/read.hpp>

ox::Result<NostalgiaPalette> loadPalette1(ox::BufferView const&buff) noexcept {
	return ox::readMC<NostalgiaPalette>(buff);
}

ox::Result<NostalgiaPalette> loadPalette2(ox::BufferView const&buff) noexcept {
	NostalgiaPalette pal;
	oxReturnError(ox::readMC(buff, pal));
	return pal;
}
```

##### Write

```cpp
#include <ox/mc/write.hpp>

ox::Result<ox::Buffer> writeSpritePalette1(NostalgiaPalette const&pal) noexcept {
	ox::Buffer buffer(ox::units::MB);
	std::size_t sz = 0;
	oxReturnError(ox::writeMC(buffer.data(), buffer.size(), pal, &sz));
	buffer.resize(sz);
	return buffer;
}

ox::Result<ox::Buffer> writeSpritePalette2(NostalgiaPalette const&pal) noexcept {
	return ox::writeMC(pal);
}
```

#### Organic Claw Example

##### Read

```cpp
#include <ox/oc/read.hpp>

ox::Result<NostalgiaPalette> loadPalette1(ox::BufferView const&buff) noexcept {
	return ox::readOC<NostalgiaPalette>(buff);
}

ox::Result<NostalgiaPalette> loadPalette2(ox::BufferView const&buff) noexcept {
	NostalgiaPalette pal;
	oxReturnError(ox::readOC(buff, &pal));
	return pal;
}
```

##### Write

```cpp
#include <ox/oc/write.hpp>

ox::Result<ox::Buffer> writeSpritePalette1(NostalgiaPalette const&pal) noexcept {
	ox::Buffer buffer(ox::units::MB);
	oxReturnError(ox::writeOC(buffer.data(), buffer.size(), pal));
	return buffer;
}

ox::Result<ox::Buffer> writeSpritePalette2(NostalgiaPalette const&pal) noexcept {
	return ox::writeOC(pal);
}
```

#### Claw Example

##### Read

```cpp
#include <ox/claw/read.hpp>

ox::Result<NostalgiaPalette> loadPalette1(ox::BufferView const&buff) noexcept {
	return ox::readClaw<NostalgiaPalette>(buff);
}

ox::Result<NostalgiaPalette> loadPalette2(ox::BufferView const&buff) noexcept {
	NostalgiaPalette pal;
	oxReturnError(ox::readClaw(buff, pal));
	return pal;
}
```

##### Write

```cpp
#include <ox/claw/write.hpp>

ox::Result<ox::Buffer> writeSpritePalette(NostalgiaPalette const&pal) noexcept {
	return ox::writeClaw(pal);
}
```

