# WebAssembly Memory Management Library

The `memory.wasm` library is very important to the inner-workings of everything
else in this series of WebAssembly libraries. Of all of the things it implements,
the most important subject is it's dynamic memory allocator. The methods it
implements behave identically to those in the libc specification.

## Example Use (WAST)

```wast
(func $main (export "main") (param $argc i32) (param $argv i32) (result i32)
  (local $ptr i32) (local $i i32)
  i32.const 26
  call $malloc
  local.set $ptr
  
  ;; Populate the allocated space
  i32.const 0
  local.set $i

  (block $_end_populate
    (loop $_populate
      (block $_populate_loop_prologue
        local.get $i
        i32.const 26
        i32.lt_u
        br_if $_populate_loop_prologue
        br $_end_populate)
      
      local.get $i
      local.get $ptr
      i32.add

      local.get $i
      i32.const 0x41
      i32.add

      i32.store8
      
      ;; $_populate epilogue
      local.get $i
      i32.const 1
      i32.add
      local.set $i
      br $_populate))
  
  i32.const 1
  local.get $ptr
  i32.const 26
  
  call $write
  drop
  
  i32.const 0)
```

## Heap Structure

For those that are curious, the heap structure that this library defines doesn't
differ much from that of `dlmalloc`, one of the most infamous general purpose
allocators. Below is a diagram of a single free block of data, that is, no data
is being stored there.

```
byte 1          2          3          4
     +----------+----------+----------+----------+
     |                                           |
     |       CUMULATIVE BLOCK SIZE (bytes)       |
     |                                           |
     +----------+----------+----------+----------+
     |                                           |
     |              POINTER FIELDS               |
     |            - Next free block              |
     |          - Previous free block            |
     |        - Next smallest free block         |
     |         - Next largest free block         |
     |                                           |
     +----------+----------+----------+----------+
     |                                           |
     |                DEAD SPACE                 |
     |                     .                     |
     |                     .                     |
     |                     .                     |
     |                                           |
     +----------+----------+----------+----------+
```

The header of each free block consists of five `i32` fields, corresponding to 20
bytes total. The first is simply just the size of the entire block, in bytes.
This figure includes the 20 byte header.

The next 16 bytes correspond to a vector of four pointers that allow the
library's `malloc` and `free` implementations to navigate around the heap to
find what they are looking for. The locations that these pointers point to are
described in the diagram above. The fact that all free blocks have these forms
the basis for an intertwined pair of doubly-linked lists: one for order by
address, and one for order by size.

Pointers that cannot point anywhere because their would-be destinations don't
exist, like in the case that the smallest block on the list has no smaller
blocks to point to, have the value in the global variable called
`$DEAD_END_POINTER`.

The value of this global may change in the future, but at the time of writing,
this value is (signed) `-1`, or (unsigned) `0xFFFFFFFF`.

Also important to note, is that the allocator keeps an internal note of where
the first free block on the heap is, also known as the "head" of the free list.

Exact implementation details may be found in the code.

## Imports

The Memory Management WebAssembly Library requires the import of certain objects
to function properly.

### env.memory

This library requires access to a `WebAssembly.Memory` object, which can be
given to the library with the following code:

```javascript
let heap_memory = new WebAssembly.Memory({ initial: 1 });
let library = await WebAssembly.instantiate(wasmBuffer, {
  env: {
    memory: heap_memory
  },
  ...
});

// Initialize the heap
library.instance.exports.init();
```

## Exports

This library defines several methods for your use.

### `$malloc(i32 $size) -> i32`

The main attraction of this module: the allocator method. This function will
take in a number of bytes that the user program wishes to allocate, do some
magic with the memory, and return a pointer to the block of memory that was
allocated.

#### Parameters

- `$size` (`i32`): The number of bytes that you want to allocate on the heap.

#### Result

**`i32`**

A pointer to the location in memory in which you may use the memory.

#### Trap Safety

As the allocator currently does not have the ability to grow the heap,
allocating more data than is available in linear memory will result in an
`unreachable` trap.

#### Example

```wast
i32.const 256
call $malloc
local.set $input

i32.const 1
local.get $input

i32.const 256
local.get $input
call $read_stdin

call $write
```

**Possible Output**

```
Input: Hello, world!
Hello, world!
```

### `$calloc(i32 $size) -> i32`

This method is a wrapper of malloc, allocating a block of data of the requested
size, clearing it's contents, and returning the pointer. This method can be
used, for example, where there is not guarantee that a string you have in memory
ends with a null byte (assuming c-style strings).

#### Parameters

- `$size` (`i32`): The size of the block you are requesting.

#### Result

**`i32`**

A pointer to the newly allocated and cleared block.

#### Trap Safety

This malloc uses `$malloc` internally, and therefore inherits the risk of
hitting an `unreachable` trap if the size of data to be allocated cannot fit
anywhere in linear memory.

#### Example

```wast
call $init ;; Make sure the heap is cleared.

i32.const 24
call $malloc
local.tee $ptr
i32.const 24
i32.const 0x41
call $fill_mem

local.get $ptr
call $free

i32.const 24
call $calloc
local.set $input

i32.const 1
local.get $input

i32.const 24
local.get $input
call $read_stdin

call $write
```

**Possible Output**

```
Input: shorttext
shorttext
```

> Instead of showing the short text and then padded with 'A' to fit a length of
> 24, $calloc did it's job correctly, and there are no memory artifacts

### `$realloc(i32 $ptr, i32 $new_size) -> i32`

This method reallocates a block of data to a new size, if necessary. If the
position of the block must move, the data inside will be copied to the new
position in memory.

> **SECURITY NOTICE**: This method makes no additional effort to clear data from
> the old block if movement of the buffer is necessary. If you are storing
> sensitive information in the block, please use $crealloc instead.

#### Parameters

- `$ptr` (`i32`): A pointer to the block to be reallocated
- `$new_size` (`i32`): The size to reallocate to

#### Result

**`i32`**

A new pointer to the block that was reallocated with at least the number of
bytes requested available.

#### Trap Safety

Because this method uses `$malloc` internally, it is possible to attempt to
reallocate so much data that the heap cannot store it, and thus an `unreachable`
trap is thrown.

#### Example

```wast
i32.const 24
call $malloc
local.set $ptr

;; Do something; determine that you need more than 24 bytes

local.get $ptr
i32.const 100
call $realloc
local.set $ptr

;; Continue with your code like nothing happened, only you have more data to
;; play with.
```

### `$free(i32 $ptr) -> void`

This method is another one of the most important in this entire module, and
possibly in any larger project that uses it. This method takes a pointer to an
allocated block and frees it for use in other parts of the program. You must
give this method the pointer originally returned by malloc or one of it's
derivatives. As always, you should also consider the pointer you have destroyed
once you free it, so remove all references to it as soon as possible to avoid
contamination of the underlying heap structure.

> **SECURITY NOTICE**: This method **DOES NOT** delete content previously stored
> in the block. If you were storing sensitive information in the buffer, please
> use $cfree instead.

#### Parameters

- `$ptr` (`i32`): A pointer to the allocated block you wish to free up for use
  elsewhere in the system.

#### Result

This method does not return anything.

#### Trap Safety

This method should not result in a trap, though that has not been tested.

#### Example

```wast
i32.const 24
call $malloc
local.set $ptr

;; Do something with $ptr until you no longer need the data.

local.get $ptr
call $free

;; The block at $ptr has become available for use elsewhere.
```

### `$cfree(i32 $ptr) -> void

This method is a wrapper around two operations commonly done when dealing with
sensitive data. The mnemonic name of this method stands for Clear and FREE.
Simply put, this method will clear the contents of the block of data, and then
free it. "Clear" in this case refers to writing zeros to every byte of data in
the block.

Note that this method is slower than $free, so if there is no reason to clear
the block before freeing, use `$free` instead.

#### Parameters

- `ptr` (`i32`): A pointer to the allocated block you wish to free up for use
  elsewhere in the system.

#### Result

This method does not return anything.

#### Trap Safety

This method should not result in a trap, though that has not been tested.

#### Example

```wast
i32.const 256
call $malloc
local.set $ptr

;; Do something that attackers shouldn't be able to see, like get a password
;; into the buffer at $ptr.

;; Determine you no longer have a use for the data in the buffer, but want to
;; dispose of it carefully.

local.get $ptr
call $cfree

;; Now the sensitive data has been erased and the block has been freed.
```

### `$memcpy(i32 $source, i32 $size, i32 $dest) -> void`

This method copies a region of memory from a source to a destination, moving
`$size` bytes. Note that this method does not delete the source data, so if
handling sensitive data, please use $memmov.

#### Parameters

- `$source` (`i32`): A pointer to the source pool of data to copy.
- `$size` (`i32`): The number of bytes to copy from the old buffer.
- `$dest` (`i32`): A pointer to the destination pool of data.

#### Result

This method does not return anything.

#### Trap Safety

This method should not result in a trap, though that has not been tested.

#### Example

```wast
;; Earlier in the file:
(data (i32.const 0) "ABD\n\x00")

;; Later
i32.const 5
call $malloc
local.set $ptr

i32.const 0
i32.const 5
local.get $ptr
call $memcpy

local.get $ptr
i32.const 2
i32.add
i32.const 0x43
i32.store

local.get $ptr
call $print_cstr

;; Like a responsible programmer, free the block
local.get $ptr
call $free
```

**Possible Output**

```
ABC
```

### `$memmov(i32 $source, i32 $size, i32 $dest) -> void`

This method simply copies, then erases the data from a source pool of data to a
destination. In other words, this is the secure variant of `$memcpy`. If you are
not storing sensitive information, please use `$memcpy` instead.

#### Parameters

- `$source` (`i32`): A pointer to the source pool of data to move.
- `$size` (`i32`): The number of bytes to copy from the old buffer.
- `$dest` (`i32`): A pointer to the destination pool of data.

#### Result

This method does not return anything.

#### Trap Safety

This method should not result in a trap, though that has not been tested.

#### Example

```wast
;; Securely move data away from something

local.get $old_ptr
i32.const 256
local.get $new_ptr
call $memmov

;; Now $old_ptr does not have access to the data
```

