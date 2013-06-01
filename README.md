# ZeevexConcurrency

ZeevexConcurrency provides some useful concurrency abstractions on top of
the relatively low-level facilities provided by Ruby itself. The goal of
this package is to make concurrent programming easier, more powerfer,
more expressive, and less error-prone.

All of the library is written as portably as possible so that it can run
on all major Ruby implementations that provide the same low-level concurrency
primitives: Threads, Mutexes, Monitors, CondVars, and Queues. In addition,
the Atomic gem is used for atomic references, and Atomic itself is very portable.

## Compatibility

Ruby implementations supported and tested with:

- MRI/CRuby/YARV 1.9.2+
- MRI/CRuby 1.8.7
- JRuby 1.7

Rubinius 2, MacRuby, RubyMotion, Maglev, and mRuby have not been tested, but they are
definitely targets.

The fundamental carrier of concurrent execution used by this gem is the Ruby Thread.
Multi-process concurrency is outside the scope of it, and there are many fine gems
which address that approach.

Fibers are neither required, nor used, nor even (at the moment) tested against.

## Motivation

You might think the currently support platform list is a bit strange, as only
JRuby provides true parallel Ruby code execution thanks to MRI's Global Interpreter
Lock. That does not make the library any less useful for code which wants to make 
many slow I/O operations run concurrently, even on Ruby 1.8. Some styles of 
concurrent programming can make even non-parallel algorithms more simple or clear 
to express.

You might also think that the Ruby platforms which support truly parallel threads
generally have rich concurrency libraries of their own.

- JRuby - comes with java.util.concurrent, the JSR-166 fork/join framework, and
  countless third party libraries
- Rubinius - Actor library
- MacRuby, RubyMotion - Grand Central Dispatch, event loops, and other 
  iOS/OS X/Cocoa concurrency constructs

This is true, but each has a very different set of "native" libraries. The goal 
of this gem is to provide a portable interface across all Ruby implementations.
In the future, native concurrency facilities might of course be used to optimize 
certain features.

## Batteries Which Are Included

Rather than being a set of single-purpose gems, this is a relatively sprawling 
collection. There are a couple of reasons for that. First, parts of this library
build on others, so it's just easier. More importantly, parts of this library
are really only useful if there is some integration between them. 

For example, Futures can use EventLoops as work queues, but EventLoops return 
Promises or Futures as handles to submitted computations.

The library can be divided into a few major systems, plus some useful stand-alone
pieces.

### The Major Systems

- Delayed/Deferred values: Futures, Promises, Delays
  - Multiplexes of Delayed/Deferred values to allow efficient group operations
  - A callback system for Delayed/Deferred values
- Oz-like Dataflow variables (built atop Futures)
- Thread pools and Event Loops
- "Scope" related facilities
  - ThreadBoundObject - a wrapper class which allows only one thread access to an object
  - Var - something like Clojure's Vars

### The Miscellany

- A Synchronized wrapper for objects to make every single public method thread-safe
  This is much like synchronized collections in Java. Low performance, high ease of use.
- A parallel map implementation for Enumerable collections (Enumerable#pmap)

### Incomplete or planned

- A richer set of locking facilities, such as: Read/Write, Semaphores, Barriers
- CSP/Go-like object channels
- Integration / compatibility / co-existence with the Celluloid Actor framework
- Fork/Join framework

## Installation

Add this line to your application's Gemfile:

    gem 'zeevex_concurrency'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install zeevex_concurrency

## Usage

Watch this space.

You can also read the rspec files for some hints, but due to the complexity of testing
concurrent code, they are not always very readable. I intend to improve that where I can.

## Related and Recommended Gems

- [CountDownLatch](https://github.com/benlangfeld/countdownlatch) - used heavily
- [Atomic](https://github.com/headius/ruby-atomic) - atomic references for several Ruby platforms
- [Celluloid](https://github.com/celluloid/celluloid) - actor-based concurrency
- [Agent](https://github.com/igrigorik/agent) - Go-like channels
- [Concurrency](https://github.com/mental/concurrent) - Mentalguy's "Omnibus" Concurrency gem, 
  which is far more sophisticated and complete, but somewhat aged and unmaintained

## See Also

- The Var system was taken as closely as possible from [Clojure](http://clojure.org/vars)
- Scala's Futures and Promises doc [SIP-14](http://docs.scala-lang.org/sips/pending/futures-promises.html) 
  was a large influence

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
