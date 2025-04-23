# Single executable ascli

The goal here is to build the tool as a compiled single executable

Initially, `rubyc` (gem [`ruby-packer`](https://github.com/pmq20/ruby-packer) and [here](https://github.com/you54f/ruby-packer)) was used to build a single executable.

<https://www.tebako.org/>

A modern version of this is now used: [`tebako`](https://github.com/tamatebako/tebako) for which a container is provided.

```bash
make GEM_VERSION=4.11.0
```
