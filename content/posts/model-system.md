---
title:  "Ox Model System"
author: Gary Talent
description: "A Poor Mans Reflection"
categories: ["Tech", "Programming"]
images:
- /dt-logo.png
tags: ["cpp", "programming", "reflection", "serialization", "nostalgia", "ox"]
date: 2023-01-30
showtoc: true
---

Note: this is based on the version of Ox in this commit in the [Nostalgia repo](https://git.drinkingtea.net/drinkingtea/nostalgia):
[5fa614ab83ee0fd080ccb5f9465e086199777859](https://git.drinkingtea.net/drinkingtea/nostalgia/src/commit/461e3d61efc9676801ae4b8f13b7ec6866bdb53f)

## Synopsis
In languages like Go and Python, there is a feature called reflection.
This essentially allows functions to iterate over arbitrary struct types to get
or set its data, or simply get information about the type.
Reflection is most commonly used for object serialization, but can be useful
for a wide variety of things.

## True Reflection
Here is an example from the JSON package of the Go standard library:
```go
type ColorGroup struct {
	ID     int
	Name   string
	Colors []string
}
group := ColorGroup{
	ID:     1,
	Name:   "Reds",
	Colors: []string{"Crimson", "Red", "Ruby", "Maroon"},
}
b, err := json.Marshal(group) // this is all it takes to serialize a ColorGroup
```

The ```ColorGroup``` type does not require any additional functions to support JSON
reading or writing.
There is similar support for Go's GOB format.

## The Boost Approach

C++ does not have a reflection system.
There is a serious proposal to add one, but its approval and implementation
remains years away.
To compensate for this Boost created an interesting API for their [serialization
system](https://www.boost.org/doc/libs/1_72_0/libs/serialization/doc/tutorial.html).

Here is a modified example taken from the Boost documentation:
```cpp
struct gps_position {
	int degrees;
	int minutes;
	float seconds;
	gps_position(){};
	gps_position(int d, int m, float s):
		degrees(d), minutes(m), seconds(s) {}
};
template<class Archive>
void serialize(Archive &ar, gps_position &g, const unsigned int version) {
    ar & g.degrees;
    ar & g.minutes;
    ar & g.seconds;
}
int main() {
	std::ifstream ifs("filename");
	boost::archive::text_iarchive ia(ifs);
	ia >> newg;
	return 0;
}
```

That same function can be used for both serialization and deserialization.
With the addition of a trivial-to-write serialize function for each type, you
have effectively created a semi-manual reflection system for iterating over
member variables.
This is more trouble than the Go equivalent, but it should actually get better
performance than Go's reflection system.
And, unlike the Go example, Ox can adopt this approach for itself.

## Ox Models

Boost had a better idea than they seem to have realized here though.
And, in spite of a genius core concept in their API design, they made some
limiting design decisions.
The biggest issue is that the Archive type is never given the names of the
members.
Adding the field name would mean using a normal function and not an overloaded
operator, but there is no reason to use an overloaded operator for this.
Naming the function 'serialize' also needlessly pigeonholes the system, as
these functions could be used for a lot more than just serialization.

Given these criticisms and some advancements in the C++ language, here is an
example of the Ox model system:

```cpp
struct NostalgiaGraphic {
	static constexpr auto TypeName = "net.drinkingtea.nostalgia.core.NostalgiaGraphic";
	static constexpr auto TypeVersion = 1;
	int8_t bpp = 0;
	// rows and columns are really only used by TileSheetEditor
	int rows = 1;
	int columns = 1;
	ox::FileAddress defaultPalette;
	Palette pal;
	ox::Vector<uint8_t> pixels = {};
};

// CommonPtrWith allows the StudioConfig to const or non-const, though certain
// handlers may still require non-const
constexpr ox::Error model(auto *handler, ox::CommonPtrWith<StudioConfig> auto *o) noexcept {
	handler->template setTypeInfo<StudioConfig>();
	oxReturnError(handler->field("bpp", bpp));
	oxReturnError(handler->field("rows", rows));
	oxReturnError(handler->field("columns", columns));
	oxReturnError(handler->field("defaultPalette", defaultPalette));
	oxReturnError(handler->field("pal", pal));
	oxReturnError(handler->field("pixels", pixels));
	return {};
}
```

Ox models can also be simplified with macros:
```cpp
struct NostalgiaGraphic {
	static constexpr auto TypeName = "net.drinkingtea.nostalgia.core.NostalgiaGraphic";
	static constexpr auto TypeVersion = 1;
	int8_t bpp = 0;
	// rows and columns are really only used by TileSheetEditor
	int rows = 1;
	int columns = 1;
	ox::FileAddress defaultPalette;
	Palette pal;
	ox::Vector<uint8_t> pixels = {};
};

oxModelBegin(NostalgiaGraphic)
	oxModelField(bpp)
	oxModelField(rows)
	oxModelField(columns)
	oxModelField(defaultPalette)
	oxModelField(pal)
	oxModelField(pixels)
oxModelEnd()
```
The macros are the preferred way to define models, as the generated model
function can be updated without having to modify all the existing models.

If you want the model field names to differ from those of the struct, you can
call ```oxModelFieldRename``` instead of ```oxModelField```:
```cpp
oxModelBegin(StudioConfig)
	oxModelFieldRename(active_tab_item_name, activeTabItemName)
	oxModelFieldRename(project_path, projectPath)
	oxModelFieldRename(open_files, openFiles)
	oxModelFieldRename(show_project_explorer, showProjectExplorer)
oxModelEnd()
```

### Type Identification

Notice that the modeled structs all have TypeName and TypeVersion fields.
These allow a serialized object to be mapped to the appropriate type.
Unlike Boost serialization, a single Ox model does not map to multiple
versions.
Old versions of a type should be duplicated.

That approach would look something like this:
```cpp
struct Configv1 {
	static constexpr auto TypeName = "net.myorg.app.Config";
	static constexpr auto TypeVersion = 1;
	ox::String projectPath;
	ox::Vector<ox::String> openFiles;
	int logLevel = 0;
};
constexpr ox::Error model(auto *handler, ox::CommonPtrWith<Configv1> auto *o) noexcept {
	handler->template setTypeInfo<Configv1>();
	oxReturnError(handler->field("projectPath", &projectPath));
	oxReturnError(handler->field("openFiles", &openFiles));
	return {};
}
struct Config {
	static constexpr auto TypeName = "net.myorg.app.Config";
	static constexpr auto TypeVersion = 2;
	ox::String projectPath;
	ox::Vector<ox::String> openFiles;
	int logLevel = 0;
};
constexpr ox::Error model(auto *handler, ox::CommonPtrWith<Config> auto *o) noexcept {
	handler->template setTypeInfo<Config>();
	oxReturnError(handler->field("projectPath", &projectPath));
	oxReturnError(handler->field("openFiles", &openFiles));
	oxReturnError(handler->field("logLevel", &logLevel));
	return {};
}
```

You might notice that the previous examples all placed the ```TypeName``` and
```TypeVersion``` fields in the body of the struct, but it is also possible to
define them outside the struct.

```cpp
struct Config {
	ox::String projectPath;
	ox::Vector<ox::String> openFiles;
	int logLevel = 0;
};

template<typename Str = const char*>
constexpr Str getModelTypeName(Config*) noexcept {
	return "net.myorg.app.Config";
}

constexpr auto getModelTypeVersion(Config*) noexcept {
	return 2;
}
```

Placing them in the struct is preferred, but that is not always an option (i.e.
a type from an external library).
With the type info already living in the struct, the only use of the model is
to pass the fields to the handlers.
Once C++ receives proper reflection support, most of models can be deleted, but
the type identifiers will still have uses.

## Type Descriptors

The [Metal Claw](/posts/metal-claw) serialization format does not store the
structure of the data.
The reader of the data is responsible for knowing how to read the data.

That works for a lot of cases, so long as you have code that knows the
structure of the data.
But ideally, the structure of the data will be stored along side the data
somewhere, even if it is not interspersed with the data as it is in a format
like JSON or MessagePack.

It would be nice to have a way to handle data from an unrelated program that
knows nothing of the matching type.
Ideally, we could take the ```TypeName``` and ```TypeVersion``` stored as a
header to the data (or some stand in identifier that might map to those) and
look up a descriptor of the type if needed.
And Ox provides support for exactly that.
Type descriptors are generated through the model system, so each type with a
model already has what it needs to have a type descriptor.

Here is an example of how type descriptor generation is done in *Nostalgia Studio*.
```cpp
template<typename T>
ox::Error Project::writeObj(const ox::String &path, const T *obj, ox::ClawFormat fmt) noexcept {
	// write MetalClaw
	oxRequireM(buff, ox::writeClaw(obj, fmt));
	// write to FS
	oxReturnError(writeBuff(path, buff));
	// write type descriptor
	if (m_typeStore.get<T>().error) {
		oxReturnError(ox::buildTypeDef(&m_typeStore, obj));
	}
	// write out type store
	static constexpr auto descPath = "/.nostalgia/type_descriptors";
	oxReturnError(mkdir(descPath));
	for (const auto &t : m_typeStore.typeList()) {
		oxRequireM(typeOut, ox::writeClaw(t, ox::ClawFormat::Organic));
		// replace garbage last character with new line
		typeOut.back().value = '\n';
		// write to FS
		const auto typePath = ox::sfmt("{}/{}", descPath, buildTypeId(*t));
		oxReturnError(writeBuff(typePath, typeOut));
	}
	fileUpdated.emit(path);
	return OxError(0);
}
```

*Nostalgia Studio* always writes out type descriptors alongside any data
written.
That way, any data can be handled arbitrarily by any program with precise
knowledge of its actual type.

Here is the TileSheet type descriptor, along with the type descriptors of its
dependencies;
```json
{
        "fieldList" : 
        [
                {
                        "fieldName" : "bpp",
                        "typeId" : "B.int8;0"
                },
                {
                        "fieldName" : "defaultPalette",
                        "typeId" : "net.drinkingtea.ox.FileAddress;1"
                },
                {
                        "fieldName" : "subsheet",
                        "typeId" : "net.drinkingtea.nostalgia.core.TileSheet.SubSheet;1"
                }
        ],
        "primitiveType" : 5,
        "typeName" : "net.drinkingtea.nostalgia.core.TileSheet",
        "typeVersion" : 2
}
{
        "fieldList" : 
        [
                {
                        "fieldName" : "name",
                        "typeId" : "net.drinkingtea.ox.BasicString#8#;1"
                },
                {
                        "fieldName" : "rows",
                        "typeId" : "B.int32;0"
                },
                {
                        "fieldName" : "columns",
                        "typeId" : "B.int32;0"
                },
                {
                        "fieldName" : "subsheets",
                        "subscriptLevels" : 1,
                        "subscriptStack" : 
                        [
                                {
                                        "subscriptType" : 4
                                }
                        ],
                        "typeId" : "net.drinkingtea.nostalgia.core.TileSheet.SubSheet;1"
                },
                {
                        "fieldName" : "pixels",
                        "subscriptLevels" : 1,
                        "subscriptStack" : 
                        [
                                {
                                        "subscriptType" : 4
                                }
                        ],
                        "typeId" : "B.uint8;0"
                }
        ],
        "primitiveType" : 5,
        "typeName" : "net.drinkingtea.nostalgia.core.TileSheet.SubSheet",
        "typeVersion" : 1
}
{
        "fieldList" : 
        [
                {
                        "fieldName" : "type",
                        "typeId" : "B.int8;0"
                },
                {
                        "fieldName" : "data",
                        "typeId" : "net.drinkingtea.ox.FileAddress.Data"
                }
        ],
        "primitiveType" : 5,
        "typeName" : "net.drinkingtea.ox.FileAddress",
        "typeVersion" : 1
}
{
        "fieldList" : 
        [
                {
                        "fieldName" : "path",
                        "typeId" : "B.string"
                },
                {
                        "fieldName" : "constPath",
                        "typeId" : "B.string"
                },
                {
                        "fieldName" : "inode",
                        "typeId" : "B.uint64;0"
                }
        ],
        "primitiveType" : 6,
        "typeName" : "net.drinkingtea.ox.FileAddress.Data",
        "typeVersion" : 1
}
{
        "primitiveType" : 4,
        "typeName" : "net.drinkingtea.ox.BasicString",
        "typeParams" : 
        [
                "8"
        ],
        "typeVersion" : 1
}
```

Types with a ```typeName``` beginning with ```B.``` are builtin types. At the
moment, ```BasicString``` is a semi-builtin type, which is why it has no
fields.
It will probably move toward being a fully custom type at some point.

The type descriptor system (which lives in Ox's model module), can generate
these type descriptors for any model.

### ModelValue

Type descriptors by themselves guarantee that your data's structure will be
known in the future, but they need an additional system to use.
For that, Ox provides a ```ModelValue``` type that ingests
the type descriptors and conform to the type given.
```ModelValue``` basically dynamically recreates arbitrary types at runtime.
```ModelValue``` implementations of your types will be a lot slower and larger
in memory than the real thing, but they still allow you to read and write
arbitrary data.

To load a type descriptors into ```ModelValue```, we will first need a
TypeStore.
Ox does not supply a working ```TypeStore``` for reading type descriptors, only
for caching in memory new ones generated in the current process.
To load type descriptors, you will need to extend ```ox::TypeStore```.

Here is the implementation of ```ox::TypeStore``` used by *Nostalgia*:
```cpp
class TypeStore: public ox::TypeStore {
	private:
		ox::FileSystem *m_fs = nullptr;

	public:
		constexpr explicit TypeStore(ox::FileSystem *fs) noexcept: m_fs(fs) {
		}

	protected:
		ox::Result<ox::UniquePtr<ox::DescriptorType>> loadDescriptor(ox::CRStringView typeId) noexcept override {
			constexpr ox::StringView descPath = "/.nostalgia/type_descriptors";
			auto path = ox::sfmt("{}/{}", descPath, typeId);
			oxRequire(buff, m_fs->read(path));
			auto dt = ox::make_unique<ox::DescriptorType>();
			oxReturnError(ox::readClaw<ox::DescriptorType>(buff, dt.get()));
			return dt;
		}
};
```

With this ```TypeStore```, we can use ```ModelValue``` to create arbitrary
types at runtime:
```cpp
	TypeStore ts(...);
	auto header = readClawHeader(buff).unwrap();
	auto t = ts->template getLoad("net.drinkingtea.nostalgia.core.TileSheet", 1, {}).unwrap();
	ModelObject obj;
	oxIgnoreError(obj.setType(t));
	oxIgnoreError(obj["bpp"].set<int8_t>(4)); // ok
	oxIgnoreError(obj["bpp"].set<ox::String>("asdf")); // will panic due to type mismatch
	oxIgnoreError(obj["bits_per_pixel"].set(4)); // will panic because bits_per_pixel does not exist in TileSheet
	;
```


## Serialization

As already mentioned as the primary application, Ox models exist to make
serialization trivial.
The model system is the foundation of Ox's serialization API.

As with the other serialization systems we looked at earlier, the serialization
can be done in a single line:
```cpp
const TileSheet ts;
ox::Buffer buff = ox::writeMC(&ts).unwrap();
```

Deserialization is similarly easy:
```cpp
ox::Buffer buff = ...;
TileSheet ts = ox::readMC(buff).unwrap();
```
