# Ang3lous "Angelous" programming Style/Guidance/Convention.
# Hi, I am Ang3l404ERR. A programmer, who values and respects time.
# This applies to all languages where it can take place.
___
# Rememeber:
# **Time is precious.** and should be kept/respected as such.
# **Time is of the essence.**, it's nothing to be underminded.
___
## this is the beginning of an official code convention/style that goes against "what the community discourages" type bullshit.
## I don't care if it's discouraged by the "community" if the "community" dislikes it, I could care less, go eat bug, fatty >:C.
## Other conventions are probably bad, probably stupid, probably pointless, probably long, probably x, probably y, probably z.
## I will not settle for anything less.
## Ask yourself these questions first:
> "Is this pointless?"
> "Is this unnecessarily long?"
> "Is there a better way to do this?"
> "Am I taking up too much space?"
> "Can this be modular?"
> "Can this be set in one file?"
> "Can this data type be in one parent file that all other children spawn from?"
> "Is this a waste of time?"

**The secret:**
# ***Y E S***
___
# #1 enemy: **SNAKE_CASE**.
it's just bad. It's pointless, it makes variables or constants stupidly long to type, and overall a huge waste of time.

## General Rules:
### 1. Don't be a space hog.
### Question: "What counts as a space hog?"
### Answer:
> `if (...) {...} else {...}`
> `if` newline `(...)` newline `{...}` newline `else` newline `{...}`
> `const reallylongandpointlesslyhugenamethatisjuststupid = "something extra short";`
> `const really_Long_and_Pointlessly_huge_name_that_is_just_idiotic = "extra short thing";`
### 2. If struct data can be represented in one single file, do that instead.
### 3. Don't be a fixed point in space, be a dynamic moving object that is never constrained.
### 4. Data is mutable/dynamic and should never be fixed. The only time that data should be fixed, is when it is genuinely helpful, otherwise, it's harmful and should be discarded immediately.
### 5. If any programming language allows for intense amounts of expressiveness/metaprogramming techniques/generics while cutting on time, it should ALWAYS be used.
### 6. If it does not, then it should be abandoned, discarded, thrown down a trash bin where that trash bin is thrown into a volcano. As fast as humanly possible.
# No exceptions.
___
## Rule 1. Module of huge `struct` params and constants
this:
```zig
const (...); // can be dynamic instead of fixed
const (...); // can be dynamic instead of fixed
const (...); // can be dynamic instead of fixed
pub const (...) = struct{
  const This = @This();
  (...):(...),
  (...):(...),
  (...):(...) = (...),
};
```
is bad, it's better to do this, wherever applicable:
```zig
// imports and constants are always at the top.
const This = @This();

// error sets, enums, unions and more follow after.
pub errors = error{
  errT1,
  errT2
}

// names of fields come next after the sets.
fName1:fType1,
fName2:fType2,
// and so on.

// private functions
fn init(...) This {
  return .{
    ...
  };
}

// public functions
pub fn deinit (this:This) void {
  ...
}
```
if I'm using zig, it's always going to be a version I am accustomed to, which for right now is Zig 0.16.0