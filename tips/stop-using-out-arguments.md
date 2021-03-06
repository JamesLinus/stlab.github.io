---
title: Stop using _out_ arguments
layout: page
tags: [tips]
comments: true
draft: true
---
## The Problem with Out Arguments

I have been lecturing about [Return-Value-Optimization](http://en.cppreference.com/w/cpp/language/copy_elision) for over a decade, yet I still see a lot of code written in this form:

```cpp
string x;
obj.get(x);
my_class y(x);
```

Where `string` is any non-basic type, `get()` is some function with an out argument, and `my_class::my_class()` is a constructor for some class type.

```cpp
void get(string& out) const;
...
my_class::my_class(const string& in);
```

There are several issues with the above code. Let's improve `get()` first, then we'll move on to `my_class`.

With an out parameter, the implementation of `get()` could take one of several forms: copying some existing date (such as a data member), calculating a new value and assigning it, or building up `out` to be the new value. Examples:

```cpp
void get(string& out) const { out = _member; }
void get(string& out) const { out = string("Calculated result"); }
void get(string& out) const {
    out.clear(); // Don't forget to clear, this is an out, not in/out argument!
    out += "Built up result";
}
```

The problems with these examples are legion:

1. ***Error Prone:*** The comment in the last examples points out why this is an error prone pattern. Unless you are careful, you can accidentally rely on the prior state of the object making this an in-out argument.

2. ***Inefficient:*** The compiler is required to copy the data from the source (`obj`) into the destination (`x`). This leads to expenses that can otherwise be avoided.

3. ***Ambiguous:*** The caller has no way to know if the call is in/out and it is their responsibility to clear the value before the call. This ambiguity leaves us open to errors on the calling side.

4. ***Unnecessarily Verbose:*** The code speaks for itself here: there is a lot being said to accomplish very little. This puts an undue burden on the developer, both in terms of understanding and maintaining the code.

## Rewriting Out Arguments

Let us look at how we would write these same three `get()` examples with a return value:

```cpp
const string& get() const { return _member; }
string get() const { return string("Calculated result"); }
string get() const {
	string result;
	result += "Built up result";
	return result;
}
```

This version of the code is better in every way:

1. ***Error Free:*** Because the caller does not have to pass in objects to receive the values, there are no preconditions required.

2. ***Efficient:*** There is a mistaken assumption that this piece of code is less efficient, introducing unnecessary copies. However, that has not been true for a very long time.

  In the first case, we avoid an unnecessary copy: if the client is only reading from the value, no copy takes place. (If they do need a copy, then the code is no worse than it was before.)

  In the second example, the compiler will use Return Value Optimization, which works because the result of a function is actually in the caller scope. The third example uses Named Return Value Optimization (NRVO), which is a specific sub-case of RVO. So in both cases the string is constructed in place and no copy occurs.

  RVO has been implemented in optimized builds for every compiler I've tested for over a decade. It will be required with C++17, so a compliant compiler must perform the optimization always. As of C++11, returning from a function is defined as a `move` operation, so even if the copy isn't elided, so long as the type has a move constructor, no copy occurs.

3. ***Unambiguous:*** This code also avoids the ambiguity as to if the argument is in/out, both for the implementor and the caller. What is getting modified is clear, and we are constructing only one object.

4. ***Terse:*** The code is clearly more compact than its predecessor.

Applying what we have just learned, we can clean up our original example:

```cpp
string x = obj.get();
my_class y(x);
```

We can even write the code without the temporary, and it will be no less performant:

```cpp
my_class y(obj.get());
```

This code is concise an no worse in performance that our original code.

## Improving the In Argument

We aren't looking for "no worse", we want better. So let's look at `my_class::my_class()`. The `in` argument is what is known as a _sink_ argument. A sink argument is one that is stored by, or returned from, the function. Constructors are a common source of sink arguments as the argument is often used to initialize a member. Consider a very common implementation form:

```cpp
my_class::my_class(const string& in) : _member(in) { }
```

This code is making an explicit copy of the string to store it. However, if the argument is a temporary, there is no need to copy the data into place, it can moved into place. To do that, pass the sink argument by value and move it into place:

```cpp
my_class::my_class(string x) : _member(std::move(x)) { }
```

In our calling example code, if `get()` is returning a `const string&` then the value will be copied at the call site and moved into place, but if `get()` is returning the `string` by value, then no copy is made, it is constructed directly in the argument slot, and then moved into place. Even if you were writing code in C++03, before `std::move()`, you could swap the value into place and still avoid the copy:

```cpp
my_class::my_class(string x) { swap(_member, x); }
```

## Error codes

A common usage of out params is to allow for an error state on return.  For example:

```cpp
bool getValue(std::string& out) {
    if(!canFetchValue) {
        return false;
    }
    out = fetchValue();
    return true;
}
```

With everything we have learned above we could simply treat the empty state of an object as our invalid case. Assuming fetchValue doesn't throw.

```cpp
std::string getValue() {
    if(!canFetchValue) {
        return "";
    }
    return fetchValue();
}
```

Using the empty state for objects is prefered as it removes the need for null checks at the call site.
If your type can't be constructed cheapily or has no obvious empty state, then you should consider using boost::optional (or std::optional if you are using c++17).

Let us assume that an empty string is expensive to create for the following example.

```cpp
std::optional<std::string> getValue() {
    if(!canFetchValue) {
        return {};
    }
    return fetchValue();
}
```

Here we have avoided creating a string, and a very lightweight class in the error case. This may loook strange at first but by this allows for much more expressiveness in your function signature. It tells the caller that this operation could possibly fail and has to be aware of it. It can also reduce the amount of branching at the call site, while reducing the mental overhead of having to come up with sane values.

For the default case:
```cpp
std::string value = getValue().value_or("not found");
```

Tricky default values

```cpp
int getUserInt(std::string userInput) {
    //parse user input
    return -1; //invalid
}
```

```cpp
std::optional<int> getUserInt(std::string userInput) {
    //parse user input
    return {}; //invalid
}
```
It is now obvious what the error case looks like and their is no ambiguity or worse, having to throw an exception for a common path and can avoid allocations! No more using pointers and nullptr checks to indicate/check for an empty state.

## In-Out Arguments

What if you _want_ an in-out argument? For example:

```cpp
void append(string& in_out) { in_out += "appended data"; }
```

In this case we can combine the two approaches:

```cpp
string append(string sink) { sink += "appended data"; return sink; }
```

To see how this is improves the code, consider a simple example like:

```cpp
string x("initial value");
append(x);
```

This will become:

```cpp
string x = append("initial value");
```

If you already had the object you wanted to append to, you can still do that:

```cpp
x = append(std::move(x));
```

### When to Modify In-situ

There are situations where an object has a large local part, so move is expensive, and it makes sense to modify the object in place. However, these should be treated as the exception, not the rule.

## Multiple Out Arguments

One reason for using out arguments has been to return multiple items. This case is not quite as clear cut, but I will argue that even here you should return via the function result for most cases.

Here is an example:

```cpp
void root_extension(const string& in, string& root, string& ext) {
	auto p = in.find_last_of('.');
	if (p == string::npos) p = in.size();
	root = in.substr(0, p);
	ext = in.substr(p, in.size() - p);
}

//...

string root;
string ext;
root_extension("path/file.jpg", root, ext);
```

This can be rewritten as:

```cpp
auto root_extension(const string& in) {
	auto p = in.find_last_of('.');
	if (p == string::npos) p = in.size();
	return make_tuple(in.substr(0, p), in.substr(p, in.size() - p));
}

//...

string root;
string ext;
tie(root, ext) = root_extension("path/file.jpg");
```

`std::tie` and `std::make_tuple` were added in C++11 (though available prior to that as part of Boost and then TR1).

This has most of the same advantages as single argument outputs. Unfortunately, the syntax is a bit more cumbersome because of the requirement to use `tie()`. However, in C++17 we will have [structured bindings](https://skebanga.github.io/structured-bindings/) so the invocation will look like:

```cpp
auto [root, ext] = root_extension("path/file.jpg");
```

C++17 also includes an `std::apply()` function that can be used to expand a tuple into a set of arguments. So you will be able to write:

```cpp
cout << apply([](string root, const string& ext){
	return move(root) + "-copy" + ext;
}, root_extension("path/file.jpg")) << endl;
```

And this will print:

```
path/file-copy.jpg
```

Without ever copying a string!

`apply()` is available today on Mac in `<experimental/tuple>`.

## Final thoughts

As with all goals, if you find case where using an out argument is better than using the function result, please do (and start a discussion here on the topic) but in most use cases I find that out arguments lose by all measures compared to using function results.
