;; module memory.wasm
;;
;; An SDK library that implements many of the libc memory management functions.
;; This module is split up into multiple parts:
;;
;; 1. A dynamic memory allocator implementation based on the famous dlmalloc
;; algorithm for WebAssembly, written in WebAssembly text format.
;; 
;; This part sets out to accomplish an important task that is sadly not
;; implemented in modern WebAssembly, young as it is. That task is to make
;; efficient use of the linear memory system WebAssembly gives it's modules so
;; that they can use memory instead of working with meaningless numbers only.
;; 
;; Want to pass a string to a function? Simple give it a pointer to a string in
;; linear memory. Same idea goes for C-style structs, and even more complex
;; data systems like JavaScript objects and arrays, which use typeless elements.
;; 
;; 2. Memory buffer management utilities, such as memcpy, as well as derivatives
;; not implemented in libc, such as the safer equivalent for handling sensitive
;; information: memmov.
;; 
;; Writing a loop just to operate over a large group of memory takes a lot of
;; effort, and can be easy to get wrong sometimes. While this part of the
;; memory.wasm SDK module is certainly far less valuable than the dynamic
;; memory allocator, looking at the allocator's source code will tell you just
;; how useful some of these methods may be.
;; 
;; @author Adrian Gjerstad
;; @license Apache-2.0
;; 
;; @docs
;; 
;;   You may find a (not quite up-to-date) copy of the documentation for every
;;   method in this module in the file called  `memory.md` in this directory.
;; 
;; @module
(module
  ;; import env.memory (WebAssembly.Memory)
  ;;
  ;; The memory object to operate on
  (memory (import "env" "memory") 1)
  
  ;; global $HEAP_OFFSET; immutable i32
  ;; 
  ;; This constant defines the position at which heap-dedicated memory should
  ;; start.
  ;; 
  ;; @global $HEAP_OFFSET
  ;; @export HEAP_OFFSET
  ;; 
  ;; @immutable
  ;; @internal
  (global $HEAP_OFFSET (export "HEAP_OFFSET") i32 (i32.const 0))
  
  ;; global $HEAP_SIZE; mutable i32
  ;; 
  ;; This constant defines the starting size of the heap, in bytes.
  ;; 
  ;; @global $HEAP_SIZE
  ;; @export HEAP_SIZE
  ;; 
  ;; @mutable
  ;; @internal
  (global $HEAP_SIZE (export "HEAP_SIZE") (mut i32) (i32.const 0))
  
  ;; global $HEAP_BLOCK_WIDTH; immutable i32
  ;; 
  ;; This constant defines the minimum width as well as alignment of blocks on
  ;; the heap. Blocks with arbitrary offsets and sizes should be avoided at all
  ;; costs to avoid catastrophic memory fragmentation. It is assumed that this
  ;; value is a power of two, as required by global $HEAP_BLOCK_BITWISE_REM
  ;; 
  ;; @global $HEAP_BLOCK_WIDTH
  ;; @export HEAP_BLOCK_WIDTH
  ;; 
  ;; @immutable
  ;; @internal
  (global $HEAP_BLOCK_WIDTH (export "HEAP_BLOCK_WIDTH") i32 (i32.const 64))

  ;; global $HEAP_BLOCK_BITWISE_REM; immutable i32
  ;; 
  ;; This constant is simply the result of an optimization done when converting
  ;; requested sizes to sizes aligned by the baseline $HEAP_BLOCK_WIDTH interval
  ;; global. It is calculated by taking the position of the bit that global
  ;; $HEAP_BLOCK_WIDTH sets, as it is a power of two, and setting all lesser
  ;; significant bits to 1, clearing the power bit in the process.
  ;;
  ;; In other words, the value of this global is $HEAP_BLOCK_WIDTH - 1.
  ;; 
  ;; Examples: 
  ;; $HEAP_BLOCK_WIDTH = 64; $HEAP_BLOCK_BITWISE_REM = 0x3F or 63.
  ;; 
  ;; @global $HEAP_BLOCK_BITWISE_REM
  ;; @export HEAP_BLOCK_BITIWSE_REM
  ;; 
  ;; @immutable
  ;; @internal
  (global $HEAP_BLOCK_BITWISE_REM (export "HEAP_BLOCK_BITWISE_REM") i32 (i32.const 0x3F))

  ;; global $DEAD_END_POINTER; immutable i32
  ;; 
  ;; This constant sets the value used to distinguish between pointers to valid
  ;; positions in memory and pointers used as stand-ins for nullptr. The safest
  ;; value of this since we are working with WebAssembly linear memory is to use
  ;; 0xFFFFFFFF (8 F's), or a negative one when using signed i32s.
  ;;
  ;; @global $DEAD_END_POINTER
  ;; @export DEAD_END_POINTER
  ;; 
  ;; @immutable
  ;; @internal
  (global $DEAD_END_POINTER (export "DEAD_END_POINTER") i32 (i32.const 0xFFFFFFFF))

  ;; global $NEXT_PTR_OFFSET; immutable i32
  ;; 
  ;; This constant sets the the offset of the pointer to a free block to get to
  ;; the blocks next pointer in memory. In other words, this is the relative
  ;; position in a free block that stores a pointer pointing to the next free
  ;; block in memory.
  ;; 
  ;; @global $NEXT_PTR_OFFSET
  ;; @export NEXT_PTR_OFFSET
  ;; 
  ;; @immutable
  ;; @internal
  (global $NEXT_PTR_OFFSET (export "NEXT_PTR_OFFSET") i32 (i32.const 4))

  ;; global $PREV_PTR_OFFSET; immutable i32
  ;; 
  ;; This constant sets the the offset of the pointer to a free block to get to
  ;; the blocks previous pointer in memory. In other words, this is the relative
  ;; position in a free block that stores a pointer pointing to the previous
  ;; free block in memory.
  ;; 
  ;; @global $PREV_PTR_OFFSET
  ;; @export PREV_PTR_OFFSET
  ;; 
  ;; @immutable
  ;; @internal
  (global $PREV_PTR_OFFSET (export "PREV_PTR_OFFSET") i32 (i32.const 8))

  ;; global $SMALL_PTR_OFFSET; immutable i32
  ;; 
  ;; This constant defines the relative position in a free block that stores a
  ;; pointer pointing to the next smallest free block in memory.
  ;; 
  ;; @global $SMALL_PTR_OFFSET
  ;; @export SMALL_PTR_OFFSET
  ;; 
  ;; @immutable
  ;; @internal
  (global $SMALL_PTR_OFFSET (export "SMALL_PTR_OFFSET") i32 (i32.const 12))
  
  ;; global $LARGE_PTR_OFFSET; immutable i32
  ;; 
  ;; This constant defines the relative position in a free block that stores a
  ;; pointer pointing to the next largest free block in memory.
  ;; 
  ;; @global $LARGE_PTR_OFFSET
  ;; @export LARGE_PTR_OFFSET
  ;; 
  ;; @immutable
  ;; @internal
  (global $LARGE_PTR_OFFSET (export "LARGE_PTR_OFFSET") i32 (i32.const 16))
  
  ;; global $FREE_LIST_HEAD; mutable i32
  ;; 
  ;; This global tells this module where the head of the free list is in
  ;; linear memory.
  ;; 
  ;; @global $FREE_LIST_HEAD
  ;; @export FREE_LIST_HEAD
  ;; 
  ;; @mutable
  ;; @internal
  (global $FREE_LIST_HEAD (export "FREE_LIST_HEAD") (mut i32) (i32.const 0))

  ;; func $init() -> void
  ;; 
  ;; This function initializes the heap based on the globals defined above.
  ;; 
  ;; @func $init
  ;; @export init
  ;; 
  ;; @internal
  (func $init (export "init")
    (local $pointer_offset i32)
    ;; Initialize locals
    i32.const 4
    local.set $pointer_offset

    ;; Initialize globals
    memory.size
    i32.const 0x10000
    i32.mul
    global.get $HEAP_OFFSET
    i32.sub
    global.set $HEAP_SIZE

    ;; Write the size of the free block to memory
    global.get $HEAP_OFFSET
    global.get $HEAP_SIZE
    i32.store
    
    ;; Write the four pointers to memory
    (block $_stop_writing_pointers
      (loop $_write_pointers
        global.get $HEAP_OFFSET
        local.get $pointer_offset
        i32.add
        global.get $DEAD_END_POINTER
        i32.store
        
        local.get $pointer_offset
        i32.const 4
        i32.add
        local.set $pointer_offset
        
        (block $_write_pointers_BREAK_CONDITION_1
          local.get $pointer_offset
          i32.const 20
          i32.ne
          br_if $_write_pointers
          
          ;; We are done writing pointers. Break
          br $_stop_writing_pointers)))
    
    ;; Set free list head pointer
    global.get $HEAP_OFFSET
    global.set $FREE_LIST_HEAD)
  
  ;; func $align_size_to_blocks(i32 size) -> i32
  ;; 
  ;; This function simply converts the input size to a multiple of the minimum
  ;; block size that is large enough to fit the requested size, but not too
  ;; large, wasting space
  ;; 
  ;; @param  i32 size  The size, in bytes, to convert
  ;; 
  ;; @result i32       The size, aligned to the next highest multiple of the
  ;;                   block size
  ;; 
  ;; @func $align_size_to_blocks
  ;; @export align_size_to_blocks
  ;; 
  ;; @internal
  (func $align_size_to_blocks (export "align_size_to_blocks") (param $size i32) (result i32)
    global.get $HEAP_BLOCK_WIDTH
    local.get $size
    global.get $HEAP_BLOCK_BITWISE_REM
    i32.and
    i32.sub
    global.get $HEAP_BLOCK_BITWISE_REM
    i32.and
    local.get $size
    i32.add)

  ;; func $find_smallest_usable_block(i32 threshold) -> i32
  ;; 
  ;; This function iterates through the free list and returns a pointer to the
  ;; smallest free block that does not go below the given threshold.
  ;;
  ;; @param  i32 threshold  The threshold minimum size to hit
  ;; 
  ;; @result i32            The pointer to the smallest usable block.
  ;; 
  ;; 
  ;; @func $find_smallest_usable_block
  ;; @export find_smallest_usable_block
  ;; 
  ;; @internal
  (func $find_smallest_usable_block (export "find_smallest_usable_block") (param $threshold i32) (result i32)
    (local $free_ptr i32)
    ;; Initialize locals
    global.get $FREE_LIST_HEAD
    local.set $free_ptr
    
    (block $_escape_loop
      (loop $_loop
        (block $_is_size_too_small
          local.get $free_ptr
          i32.load
          local.get $threshold
          i32.lt_u
          br_if $_is_size_too_small
          
          ;; Block is a good candidate
          (block $_has_smaller_candidate
            local.get $free_ptr
            global.get $SMALL_PTR_OFFSET
            i32.add
            i32.load
            global.get $DEAD_END_POINTER
            i32.ne
            br_if $_has_smaller_candidate
    
            ;; The smallest good candidate has been found
            br $_escape_loop)
          
          ;; This block has a smaller candidate. Is it too small?
          (block $_is_next_smallest_too_small
            local.get $free_ptr
            global.get $SMALL_PTR_OFFSET
            i32.add
            i32.load
            i32.load
            local.get $threshold
            i32.lt_u
            br_if $_is_next_smallest_too_small
    
            ;; This block has a smaller available candidate. Try that
            local.get $free_ptr
            global.get $SMALL_PTR_OFFSET
            i32.add
            i32.load
            local.set $free_ptr
            br $_loop)
          
          ;; The next smallest candidate is too small. This is the smallest
          ;; candidate
          br $_escape_loop)
        
        ;; Current is too small
        (block $_is_next_largest_dead_end
          local.get $free_ptr
          global.get $LARGE_PTR_OFFSET
          i32.add
          i32.load
          global.get $DEAD_END_POINTER
          i32.eq
          br_if $_is_next_largest_dead_end
          
          ;; Next largest is not a dead end. Follow that and see where it takes
          ;; you
          local.get $free_ptr
          global.get $LARGE_PTR_OFFSET
          i32.add
          i32.load
          local.set $free_ptr
          br $_loop)
        
        ;; Current block is too small and no larger option exists.
        ;; This is the only available option now.
        unreachable))
    
    local.get $free_ptr)
  
  ;; func $remove_from_free_list(i32 ptr) -> void
  ;; 
  ;; This function simply removes the free block being pointed at from the free
  ;; list, leaving a gap in memory where an allocated block may be placed. Note
  ;; this does not clear or alter the memory at the pointer. Those are
  ;; operations that must be done on their own.
  ;; 
  ;; @param  i32 ptr  A pointer to the block to remove from the free list
  ;; 
  ;; @func $remove_from_free_list
  ;; @export remove_from_free_list
  ;; 
  ;; @internal
  (func $remove_from_free_list (export "remove_from_free_list") (param $ptr i32)
    (block $_is_ptr_not_the_free_list_head
      local.get $ptr
      global.get $FREE_LIST_HEAD
      i32.ne
      br_if $_is_ptr_not_the_free_list_head
      
      ;; $ptr points to the free list head. We need to update it before we
      ;; remove this block
      local.get $ptr
      global.get $NEXT_PTR_OFFSET
      i32.add
      i32.load
      global.set $FREE_LIST_HEAD)
    
    ;; Get removing!
    (block $_is_next_a_dead_end
      local.get $ptr
      global.get $NEXT_PTR_OFFSET
      i32.add
      i32.load
      global.get $DEAD_END_POINTER
      i32.eq
      br_if $_is_next_a_dead_end
      
      ;; NXT pointer points to a valid address. Fix it's pointer.
      local.get $ptr
      global.get $NEXT_PTR_OFFSET
      i32.add
      i32.load
      global.get $PREV_PTR_OFFSET
      i32.add
      
      local.get $ptr
      global.get $PREV_PTR_OFFSET
      i32.add
      i32.load
      i32.store)
    
    (block $_is_prev_a_dead_end
      local.get $ptr
      global.get $PREV_PTR_OFFSET
      i32.add
      i32.load
      global.get $DEAD_END_POINTER
      i32.eq
      br_if $_is_prev_a_dead_end
      
      ;; PRV pointer points to a valid address. Fix it's pointer.
      local.get $ptr
      global.get $PREV_PTR_OFFSET
      i32.add
      i32.load
      global.get $NEXT_PTR_OFFSET
      i32.add
      
      local.get $ptr
      global.get $NEXT_PTR_OFFSET
      i32.add
      i32.load
      i32.store)
    
    (block $_is_small_a_dead_end
      local.get $ptr
      global.get $SMALL_PTR_OFFSET
      i32.add
      i32.load
      global.get $DEAD_END_POINTER
      i32.eq
      br_if $_is_small_a_dead_end
      
      ;; SML pointer points to a valid address. Fix it's pointer.
      local.get $ptr
      global.get $SMALL_PTR_OFFSET
      i32.add
      i32.load
      global.get $LARGE_PTR_OFFSET
      i32.add
      
      local.get $ptr
      global.get $LARGE_PTR_OFFSET
      i32.add
      i32.load
      i32.store)
    
    (block $_is_large_a_dead_end
      local.get $ptr
      global.get $LARGE_PTR_OFFSET
      i32.add
      i32.load
      global.get $DEAD_END_POINTER
      i32.eq
      br_if $_is_large_a_dead_end
      
      ;; LRG pointer points to a valid address. Fix it's pointer.
      local.get $ptr
      global.get $LARGE_PTR_OFFSET
      i32.add
      i32.load
      global.get $SMALL_PTR_OFFSET
      i32.add
      
      local.get $ptr
      global.get $SMALL_PTR_OFFSET
      i32.add
      i32.load
      i32.store))
  
  ;; func $insert_free_list(i32 ptr, i32 size) -> void
  ;; 
  ;; This function inserts a new block into the free list, given it's location,
  ;; and size.
  ;; 
  ;; @param  i32 ptr   A pointer to position the new free block at
  ;; @param  i32 size  The size of the free block to insert
  ;; 
  ;; @func $insert_free_list
  ;; @export insert_free_list
  ;; 
  ;; @internal
  (func $insert_free_list (export "insert_free_list") (param $ptr i32) (param $size i32)
    (local $next_ptr i32) (local $prev_ptr i32) (local $small_ptr i32)
    (local $large_ptr i32) (local $investigate_ptr i32) (local $going_large i32)
    ;; Initialize locals
    global.get $DEAD_END_POINTER
    local.tee $next_ptr
    local.tee $prev_ptr
    local.tee $small_ptr
    local.set $large_ptr
    
    (block $_is_free_list_head_poisoned
      global.get $FREE_LIST_HEAD
      global.get $DEAD_END_POINTER
      i32.ne
      br_if $_is_free_list_head_poisoned
      
      ;; Free list head is a dead end. Fix that
      local.get $ptr
      global.set $FREE_LIST_HEAD
      
      local.get $ptr
      local.get $size
      i32.store

      local.get $ptr
      i32.const 4
      i32.add
      global.get $DEAD_END_POINTER
      i32.store

      local.get $ptr
      i32.const 8
      i32.add
      global.get $DEAD_END_POINTER
      i32.store

      local.get $ptr
      i32.const 12
      i32.add
      global.get $DEAD_END_POINTER
      i32.store

      local.get $ptr
      i32.const 16
      i32.add
      global.get $DEAD_END_POINTER
      i32.store
      
      return)

    global.get $FREE_LIST_HEAD
    local.set $investigate_ptr

    i32.const 0
    local.set $going_large
    
    (block $_done_finding_pointers
      (loop $_find_pointers
        (block $_next_pointer_found
          local.get $next_ptr
          global.get $DEAD_END_POINTER
          i32.ne
          br_if $_next_pointer_found
          
          ;; $next_ptr not yet set
          (block $_should_set_next_ptr
            local.get $investigate_ptr
            local.get $ptr
            i32.gt_u
            br_if $_should_set_next_ptr
            
            ;; Should not set next pointer
            br $_next_pointer_found)
          
          ;; Should set next pointer
          local.get $investigate_ptr
          local.set $next_ptr
          local.get $investigate_ptr
          global.get $PREV_PTR_OFFSET
          i32.add
          i32.load
          local.set $prev_ptr
          br $_done_finding_pointers)
        
        (block $_is_there_a_next_ptr
          local.get $investigate_ptr
          global.get $NEXT_PTR_OFFSET
          i32.add
          i32.load
          global.get $DEAD_END_POINTER
          i32.eq
          br_if $_is_there_a_next_ptr
          
          local.get $investigate_ptr
          global.get $NEXT_PTR_OFFSET
          i32.add
          i32.load
          local.set $investigate_ptr
          br $_find_pointers)
        
        local.get $investigate_ptr
        local.set $prev_ptr
        br $_done_finding_pointers))
    
    global.get $FREE_LIST_HEAD
    local.set $investigate_ptr

    ;; Now to find the split in size pointers
    (block $_done_finding_size_pointers
      (loop $_find_size_pointers
        (block $_direction_decided
          local.get $going_large
          i32.const 0
          i32.ne
          br_if $_direction_decided
          
          ;; Direction of travel not yet decided
          (block $_going_large
            local.get $investigate_ptr
            i32.load
            local.get $size
            i32.lt_u
            br_if $_going_large
            
            i32.const -1
            local.set $going_large
            br $_direction_decided)
          
          i32.const 1
          local.set $going_large
          br $_direction_decided)
        
        ;; Direction of travel has been decided. Begin checking.
        (block $_travelling_large
          (block $_travelling_small
            local.get $going_large
            i32.const -1
            i32.ne
            br_if $_travelling_small

            ;; We are travelling in the direction of the small pointers
            (block $_continue_finding_next_smallest
              local.get $investigate_ptr
              i32.load
              local.get $size
              i32.gt_u
              br_if $_continue_finding_next_smallest
              
              ;; Found place to insert.
              local.get $investigate_ptr
              local.set $large_ptr
              local.get $investigate_ptr
              global.get $SMALL_PTR_OFFSET
              i32.add
              i32.load
              local.set $small_ptr
              br $_done_finding_size_pointers)

            (block $_is_next_smallest_available
              local.get $investigate_ptr
              global.get $LARGE_PTR_OFFSET
              i32.add
              i32.load
              global.get $DEAD_END_POINTER
              i32.ne
              br_if $_is_next_smallest_available
              
              ;; Next smallest not available
              local.get $investigate_ptr
              local.set $small_ptr
              br $_done_finding_size_pointers)

            ;; Next smallest is available. Try that and see what happens
            local.get $investigate_ptr
            global.get $LARGE_PTR_OFFSET
            i32.add
            i32.load
            local.set $investigate_ptr

            br $_travelling_large)
          
          ;; We are travelling in the direction of the large pointers
          (block $_continue_finding_next_largest
            local.get $investigate_ptr
            i32.load
            local.get $size
            i32.gt_u
            br_if $_continue_finding_next_largest
            
            ;; Found place to insert.
            local.get $investigate_ptr
            local.set $small_ptr
            local.get $investigate_ptr
            global.get $LARGE_PTR_OFFSET
            i32.add
            i32.load
            local.set $large_ptr
            br $_done_finding_size_pointers)

          (block $_is_next_largest_available
            local.get $investigate_ptr
            global.get $SMALL_PTR_OFFSET
            i32.add
            i32.load
            global.get $DEAD_END_POINTER
            i32.ne
            br_if $_is_next_largest_available
            
            ;; Next largest not available
            local.get $investigate_ptr
            local.set $large_ptr
            br $_done_finding_size_pointers)

          ;; Next largest is available. Try that and see what happens
          local.get $investigate_ptr
          global.get $SMALL_PTR_OFFSET
          i32.add
          i32.load
          local.set $investigate_ptr

          br $_travelling_large)))

    ;; We now know the values of the next, previous, small, and large pointers
    local.get $ptr
    local.get $size
    i32.store
    
    local.get $ptr
    global.get $NEXT_PTR_OFFSET
    i32.add
    local.get $next_ptr
    i32.store
    
    local.get $ptr
    global.get $PREV_PTR_OFFSET
    i32.add
    local.get $prev_ptr
    i32.store
    
    local.get $ptr
    global.get $SMALL_PTR_OFFSET
    i32.add
    local.get $small_ptr
    i32.store
    
    local.get $ptr
    global.get $LARGE_PTR_OFFSET
    i32.add
    local.get $large_ptr
    i32.store

    (block $_next_is_dead_end
      local.get $next_ptr
      global.get $DEAD_END_POINTER
      i32.eq
      br_if $_next_is_dead_end
      
      ;; Next pointer is not a dead end. Update it's prev pointer
      local.get $next_ptr
      global.get $PREV_PTR_OFFSET
      i32.add
      local.get $ptr
      i32.store)
    
    (block $_prev_is_dead_end
      local.get $prev_ptr
      global.get $DEAD_END_POINTER
      i32.eq
      br_if $_prev_is_dead_end
      
      ;; Prev pointer is not a dead end. Update it's next pointer
      local.get $prev_ptr
      global.get $NEXT_PTR_OFFSET
      i32.add
      local.get $ptr
      i32.store)
    
    (block $_small_is_dead_end
      local.get $small_ptr
      global.get $DEAD_END_POINTER
      i32.eq
      br_if $_small_is_dead_end
      
      ;; Small pointer is not a dead end. Update it's large pointer
      local.get $small_ptr
      global.get $LARGE_PTR_OFFSET
      i32.add
      local.get $ptr
      i32.store)
    
    (block $_large_is_dead_end
      local.get $large_ptr
      global.get $DEAD_END_POINTER
      i32.eq
      br_if $_large_is_dead_end
      
      ;; Large pointer is not a dead end. Update it's small pointer
      local.get $large_ptr
      global.get $SMALL_PTR_OFFSET
      i32.add
      local.get $ptr
      i32.store))

  ;; func $truncate_for_allocation(i32 ptr, i32 size) -> void
  ;; 
  ;; This function truncates a free block by offsetting and shrinking the block
  ;; by the amount specified in size. This method does no extra work to write
  ;; new sizes or pointers to the original block being pointed to, so that is
  ;; work that must be done after if needed. DO NOT ALTER THE BLOCK BEFORE
  ;; CALLING THIS METHOD.
  ;; 
  ;; @param  i32 ptr   A pointer to the free block to truncate
  ;; @param  i32 size  The number of bytes to offset and shrink the block by
  ;; 
  ;; @func $truncate_for_allocation
  ;; @export truncate_for_allocation
  ;; 
  ;; @internal
  (func $truncate_for_allocation (export "truncate_for_allocation") (param $ptr i32) (param $size i32)
    (local $new_ptr i32)
    local.get $ptr
    call $remove_from_free_list

    local.get $ptr
    local.get $size
    i32.add
    local.tee $new_ptr
    
    local.get $ptr
    i32.load
    local.get $size
    i32.sub
    call $insert_free_list)
  
  ;; func $merge_free_blocks(i32 ptr1, i32 ptr2) -> void
  ;; 
  ;; This function joins two adjacent blocks on the free list together,
  ;; assuming the first pointer and the second pointer point to the first and
  ;; second blocks on the list, consecutively, respectively. This is the main
  ;; method this allocator uses to help prevent memory fragmentation, because
  ;; two adjacent free blocks can be joined and get viewed as one large block.
  ;;
  ;; @param  i32 ptr1  A pointer to the first block to join
  ;; @param  i32 ptr2  A pointer to the second block to join (after ptr1)
  ;; 
  ;; @func $merge_free_blocks
  ;; @export merge_free_blocks
  ;; 
  ;; @internal
  (func $merge_free_blocks (export "merge_free_blocks") (param $ptr1 i32) (param $ptr2 i32)
    (local $new_size i32)
    ;; Initialize locals
    local.get $ptr1
    i32.load
    local.get $ptr2
    i32.load
    i32.add
    local.set $new_size
    
    local.get $ptr1
    call $remove_from_free_list
    local.get $ptr2
    call $remove_from_free_list
    
    local.get $ptr1
    local.get $new_size
    call $insert_free_list)

  ;; func $merge_free_list() -> void
  ;; 
  ;; This method runs an iteration of merges across the free list, and is called
  ;; after freeing a block to merge all adjacent free blocks, avoiding memory
  ;; fragmentation.
  ;; 
  ;; @func $merge_free_list
  ;; @export merge_free_list
  ;; 
  ;; @internal
  (func $merge_free_list (export "merge_free_list")
    (local $merge_ptr i32)
    ;; Initialize locals
    global.get $FREE_LIST_HEAD
    local.set $merge_ptr
    
    (block $_done_merging
      (loop $_merge
        (block $_merge_BREAK_CONDITION_1
          local.get $merge_ptr
          global.get $DEAD_END_POINTER
          i32.eq
          br_if $_done_merging
          br $_merge_BREAK_CONDITION_1)
        
        (block $_mergeable
          local.get $merge_ptr
          i32.load
          local.get $merge_ptr
          global.get $NEXT_PTR_OFFSET
          i32.add
          i32.load
          i32.eq
          br_if $_mergeable

          local.get $merge_ptr
          global.get $NEXT_PTR_OFFSET
          i32.add
          i32.load
          local.set $merge_ptr
          br $_merge)
        
        ;; Merge these blocks
        local.get $merge_ptr
        local.get $merge_ptr
        global.get $NEXT_PTR_OFFSET
        i32.add
        i32.load
        call $merge_free_blocks
        
        br $_merge)))

  ;; func $malloc(i32 size) -> i32
  ;; 
  ;; The main attraction of this module: the allocator method. This function
  ;; will take in a number of bytes that the user program wishes to allocate,
  ;; do some magic with the memory, and return a pointer to the block of memory
  ;; that was allocated.
  ;; 
  ;; @param  i32 size  The number of bytes that you want to allocate on the heap
  ;;
  ;; @result i32       A pointer to the location in memory in which you may use
  ;;                   the memory
  ;;
  ;; @func $malloc
  ;; @export malloc
  (func $malloc (export "malloc") (param $size_ i32) (result i32)
    (local $size i32) (local $free_ptr i32)
    ;; Allow for the size the size i32 takes up so that we don't under-allocate
    local.get $size_
    i32.const 4
    i32.add
    call $align_size_to_blocks
    local.tee $size
    call $find_smallest_usable_block
    local.set $free_ptr
   
    ;; Do allocation magic
    (block $_done_allocating
      (block $_block_is_alone
        ;; if(size_at($free_ptr) == $size) block_is_alone;
        local.get $free_ptr
        i32.load
        local.get $size
        i32.eq
        br_if $_block_is_alone
        
        ;; This block is not alone. It must be truncated to allow for the space
        ;; to be allocated.
        local.get $free_ptr
        local.get $size
        call $truncate_for_allocation

        ;; Now the size on the now-overlapping block is wrong. Fix it or bad
        ;; things will happen when it is freed.
        local.get $free_ptr
        local.get $size
        i32.store

        br $_done_allocating)
      
      ;; This block is alone. Remove it from the free list.
      local.get $free_ptr
      call $remove_from_free_list

      br $_done_allocating)

    ;; Allocation done! return the pointer
    local.get $free_ptr
    i32.const 4
    i32.add)

  ;; func $calloc(i32 size) -> i32
  ;; 
  ;; This method is a wrapper of malloc, allocating a block of data of the
  ;; requested size, clearing it's contents, and returning the pointer. This
  ;; method can be used, for example, when there is no guarantee that a string
  ;; you have in memory ends with a null byte (assuming c-style strings)
  ;; 
  ;; @param  i32 size  The size of the block you are requesting.
  ;; 
  ;; @result  i32      A pointer to the newly allocated and cleared block.
  ;; 
  ;; @func $calloc
  ;; @export calloc
  (func $calloc (export "calloc") (param $size i32) (result i32)
    (local $ptr i32) (local $full_size i32) (local $i i32)
    local.get $size
    call $malloc
    local.tee $ptr
    i32.const 4
    i32.sub
    i32.load
    i32.const 4
    i32.sub
    local.set $full_size

    i32.const 0
    local.set $i
    
    (block $_done_clearing
      (loop $_clear
        (block $_clear_for_head
          local.get $i
          local.get $full_size
          i32.lt_u
          br_if $_clear_for_head
          br $_done_clearing)
        
        local.get $i
        local.get $ptr
        i32.add
        i32.const 0
        i32.store

        local.get $i
        i32.const 4
        i32.add
        local.set $i
        br $_clear))
    
    local.get $ptr)

  ;; func $realloc(i32 ptr, i32 new_size) -> i32
  ;; 
  ;; This method reallocates a block of data to a new size, if necessary. If the
  ;; position of the block must move, the data inside will be copied to the new
  ;; position in memory.
  ;; 
  ;; SECURITY NOTICE: This method makes no additional effort to clear data from
  ;; the old block if necessary. If you are storing sensitive information in the
  ;; block, please use $crealloc instead.
  ;; 
  ;; @param  i32 ptr       A pointer to the block to be reallocated
  ;; @param  i32 new_size  The size to reallocate to.
  ;; 
  ;; @result  i32          A new pointer to the block that was reallocated, with
  ;;                       at least the number of bytes requested available.
  ;; 
  ;; @func $realloc
  ;; @export realloc
  (func $realloc (export "realloc") (param $ptr i32) (param $new_size i32) (result i32)
    (local $fixed_old_size i32) (local $fixed_new_size i32) (local $first_8 i64) (local $second_8 i64) (local $new_ptr i32)
    local.get $ptr
    i32.const 4
    i32.sub
    i32.load
    local.set $fixed_old_size
    
    local.get $new_size
    i32.const 4
    i32.add
    call $align_size_to_blocks
    local.set $fixed_new_size
    
    (block $_should_move
      local.get $fixed_old_size
      local.get $fixed_new_size
      i32.ne
      br_if $_should_move
      
      ;; No need to move blocks. Just return
      local.get $ptr
      return)
    
    ;; We need to move blocks to reallocate
    local.get $ptr
    i64.load
    local.set $first_8
    local.get $ptr
    i32.const 8
    i32.add
    i64.load
    local.set $second_8
    
    ;; Now free the block
    local.get $ptr
    call $free
    local.get $new_size
    call $malloc
    local.set $new_ptr
    
    ;; Now write the first 16 bytes
    local.get $new_ptr
    local.get $first_8
    i64.store
    
    local.get $new_ptr
    i32.const 8
    i32.add
    local.get $second_8
    i64.store
    
    ;; Now copy the rest
    local.get $ptr
    i32.const 16
    i32.add
    local.get $fixed_old_size
    i32.const 20
    i32.sub
    local.get $new_ptr
    i32.const 16
    i32.add
    call $memcpy
    
    local.get $new_ptr)

  ;; func $free(i32 ptr) -> void
  ;; 
  ;; This method is another one of the most important in this entire module, and
  ;; possibly in any larger project that uses it. This method takes a pointer to
  ;; an allocated block, and frees it for use in other parts of the program. You
  ;; must give this method the pointer originally returned by malloc or one of
  ;; it's derivatives. As always, you should also consider the pointer you have
  ;; destroyed once you free it, so remove all references to it as soon as
  ;; possible to avoid contamination of the underlying heap structure.
  ;; 
  ;; SECURITY NOTICE: This method DOES NOT delete content previously stored in
  ;;                  the block. If you were storing sensitive information in
  ;;                  the buffer, use $cfree instead.
  ;; 
  ;; @param  i32 ptr  A pointer to the allocated block you wish to free up for
  ;;                  use elsewhere in the system.
  ;; 
  ;; @func $free
  ;; @export free
  (func $free (export "free") (param $ptr_ i32)
    (local $ptr i32)
    local.get $ptr_
    i32.const 4
    i32.sub
    local.tee $ptr
    local.get $ptr
    i32.load
    call $insert_free_list
    
    call $merge_free_list)

  ;; func $cfree(i32 ptr) -> void
  ;; 
  ;; This method is a wrapper around two operations commonly done when dealing
  ;; with sensitive data. The mnemonic name of this method stands for Clear and
  ;; FREE. Simply put, this method will clear the contents of the block of data,
  ;; and then free it. "Clear" in this case refers to writing zeros to every
  ;; byte of data in the block.
  ;; 
  ;; NOTE: This method is slower than $free, so if there is no reason to clear
  ;; the block before freeing, use $free instead.
  ;; 
  ;; @param  i32 ptr  A pointer to the allocated block you wish to free up for
  ;;                  use elsewhere in the system.
  ;; 
  ;; @func $cfree
  ;; @export cfree
  (func $cfree (export "cfree") (param $ptr i32)
    (local $size i32) (local $i i32)
    local.get $ptr
    i32.const 4
    i32.sub
    i32.load
    i32.const 4
    i32.sub
    local.set $size
    ;; $size contains the amount of payload data to erase
    
    i32.const 0
    local.set $i
    
    (block $_done_clearing
      (loop $_clear
        (block $_for_loop_head
          local.get $i
          local.get $size
          i32.lt_u
          br_if $_for_loop_head
          br $_done_clearing)
        
        local.get $i
        local.get $ptr
        i32.add
        i32.const 0
        i32.store

        local.get $i
        i32.const 4
        i32.add
        local.set $i
        br $_clear))
    
    local.get $ptr
    call $free)
  
  ;; func $memcpy(i32 source, i32 size, i32 dest) -> void
  ;; 
  ;; This method copies a region of memory from a source to a destination,
  ;; moving $size bytes. Note that this method does not delete the source data,
  ;; so if handling sensitive information, please use $memmov.
  ;; 
  ;; @param  i32 source  A pointer to the source pool of data to copy.
  ;; @param  i32 size    The number of bytes to copy from the old buffer.
  ;; @param  i32 dest    A pointer to the destination pool of data.
  ;; 
  ;; @func $memcpy
  ;; @export memcpy
  (func $memcpy (export "memcpy") (param $source i32) (param $size i32) (param $dest i32)
    (local $i i32)
    ;; Initialize locals
    i32.const 0
    local.set $i
    
    (block $_end_for_loop
      (loop $_for_loop
        (block $_for_loop_header
          local.get $i
          local.get $size
          i32.lt_u
          br_if $_for_loop_header
          br $_end_for_loop)
        
        local.get $dest
        local.get $i
        i32.add
        local.get $source
        local.get $i
        i32.add
        i32.load8_u
        i32.store8

        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $_for_loop)))
  
  ;; func $memmov(i32 source, i32 size, i32 dest) -> void
  ;; 
  ;; This method simply copies, then erases the data from a source pool of data
  ;; to a destination. In other words, this is the secure variant of $memcpy. If
  ;; you are not storing sensitive information, please use $memcpy instead.
  ;; 
  ;; @param  i32 source  A pointer to the source pool of data to move.
  ;; @param  i32 size    The number of bytes to move from the old buffer.
  ;; @param  i32 dest    A pointer to the destination pool of data.
  ;; 
  ;; @func $memmov
  ;; @export memmov
  (func $memmov (export "memmov") (param $source i32) (param $size i32) (param $dest i32)
    (local $i i32)
    ;; Initialize locals
    i32.const 0
    local.set $i
    
    (block $_end_for_loop
      (loop $_for_loop
        (block $_for_loop_header
          local.get $i
          local.get $size
          i32.lt_u
          br_if $_for_loop_header
          br $_end_for_loop)
        
        local.get $dest
        local.get $i
        i32.add
        local.get $source
        local.get $i
        i32.add
        i32.load8_u
        i32.store8

        local.get $source
        local.get $i
        i32.add
        i32.const 0
        i32.store8

        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $_for_loop))))

