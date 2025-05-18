---
title: "C++ Strings"
author: Gary Talent
description: "Getting C++ Strings Right"
categories: ["Tech", "Programming"]
images:
- /dt-logo.png
tags: ["cpp", "programming", "string", "strings", "c++"]
date: 2026-11-24
showtoc: true
---

C++, using only the standard library, has three different ways of representing
strings.
If using Qt, we also have QString and QStringView, which are not 1:1
replacements for std::string and string_view.

Strings are not really something that the language can reasonably simplify, but
people generally get them wrong in ways that really matter, hence the need for
this article.


## C Strings

Before getting to the modern C++ ways of representing strings, we should look
at what we started with in C.

In C, strings are merely pointers to chars.
The char pointed to will generally only be the first of an array of chars that
make up that string.
The pointer obviously does not tell you how many chars are in the string.
That information is gathered by iterating over the string until we reach a char
who's value is 0, which marks thee end of the string.

Examples of C string usage:

```c
int main() {
    const char *s = "asdf"; // sets aside 5 bytes of memory in the data section of the program
    printf("strlen of %s: %d\n", s, strlen(s));
    for (int i = 0; i < 5; ++i) {
        printf("%d: %d\n", i, s[i]);
    }
}
```

Output:

```
strlen of asdf: 4
0: 97
1: 115
2: 100
3: 102
4: 0
```

That works well for literals, but what if we need to generate a string at runtime?
We will need to run malloc or use variable length arrays.


```c
int main(int argc, const char **argv) {
    for (int i = 1; i < argc; ++i) {
        char path[64];
        sprintf(path, "Hello, %s", argv[i]);
        printf("%s\n", path);
    }
}
```

