[![Contributors](https://img.shields.io/github/contributors/AdrianGjerstad/wasm-rtk.svg?style=for-the-badge)](https://github.com/AdrianGjerstad/wasm-rtk/graphs/contributors)
[![Forks](https://img.shields.io/github/forks/AdrianGjerstad/wasm-rtk.svg?style=for-the-badge)](https://github.com/AdrianGjerstad/wasm-rtk/network/members)
[![Stars](https://img.shields.io/github/stars/AdrianGjerstad/wasm-rtk.svg?style=for-the-badge)](https://github.com/AdrianGjerstad/wasm-rtk/stargazers)
[![Issues](https://img.shields.io/github/issues/AdrianGjerstad/wasm-rtk.svg?style=for-the-badge)](https://github.com/AdrianGjerstad/wasm-rtk/issues)
[![License](https://img.shields.io/github/license/AdrianGjerstad/wasm-rtk.svg?style=for-the-badge)](https://github.com/AdrianGjerstad/wasm-rtk/blob/main/LICENSE)

<div align="center">
  <a href="https://github.com/AdrianGjerstad/wasm-rtk">
    <img src="https://upload.wikimedia.org/wikipedia/commons/1/1f/WebAssembly_Logo.svg" alt="WebAssembly" width="80" height="80"></img>
  </a>
  <h3 align="center">WebAssembly Raw Text Toolkit</h3>
  
  <div align="center">
    An array of WebAssembly libraries and more, all written in WAT by hand!
    <br/>
    <a href="#get-started">Get started &raquo;</a>
    <br/>
    <br/>
    <a href="https://github.com/AdrianGjerstad/wasm-rtk/blob/main/docs/README.md">View Documentation</a> &bull;
    <a href="https://github.com/AdrianGjerstad/wasm-rtk/issues">Report a Bug</a> &bull;
    <a href="#contibuting">Contribute</a>
  </div>
</div>

<details open>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-this-project">About This Project</a>
      <ul>
        <li><a href="#motivation">Motivation</a></li>
      </ul>
    </li>
    <li><a href="#get-started">Get Started</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#acknowledgements">Acknowledgements</a></li>
  </ol>
</details>

## About This Project

Wasm-RTk is a collection of WebAssembly development tools allowing for easier development than is initially made available in the WebAssembly environment. Beyond utilities like IO, cryptography, and artificial intelligence (maybe), I also want to build a compiler for a language that specifically implements, in WebAssembly, many of the techniques I have though of while writing these libraries, like Object Oriented Programming.

If you are interested in adding or contributing to anything in this collection, please <a href="https://github.com/AdrianGjerstad/wasm-rtk/issues">create an issue</a>.

### Motivation

This repository started with the simple idea of implementing a multipurpose websocket server, utilizing WebAssembly in the process to be as fast as possible. I quickly realized, however, that there was a problem with this plan. WebAssembly is just about as native and bare-metal as you get on the web, but that comes at the cost of having virtually nothing available to use at the start. This is why I began work on the first library in this collection.

Looking around and roadmapping what I wanted to do, I eventually came to the decision that dynamic memory allocation was something that I absolutely had to tackle early on. Next, I didn't want to use anything like Emscripten, mostly because it looked like a hassle to install and use. Furthermore, I enjoyed knowing that I was learning something knew when I decided to write said library entirely using WebAssembly Text S-Expressions.

While I don't recommend the experience of writing a full-blown dynamic memory allocator in an assembly language, it created new ideas about how much of the high-level programming language luxuries I enjoy today were created. The biggest of these was thinking about how object-oriented programming is implemented. I would go on to imagine writing yet another compiler that targets WebAssembly binaries and implements many of the features that I feel WebAssembly lacks, while maintaining it's original power.

## Get Started

If you want to get started using these libraries, I have a whole directory dedicated to documentation in this repository. You can start reading <a href="https://github.com/AdrianGjerstad/wasm-rtk/blob/main/docs/GETTING_STARTED.md">here</a>.

## Roadmap

Check the list of <a href="https://github.com/AdrianGjerstad/wasm-rtk/issues">open issues</a> to get an idea of planned additions.

## Contributing

Check out the <a href="https://github.com/AdrianGjerstad/wasm-rtk/blob/main/CONTRIBUTING.md">contributing guidelines</a> for information on contributing to this repository.

## License

The license can be found at <a href="https://github.com/AdrianGjerstad/wasm-rtk/blob/main/LICENSE">LICENSE</a>

## Acknowledgements

WebAssembly logo by <a href="https://github.com/carlosbaraza">Carlos Baraza</a>, <a href="https://creativecommons.org/publicdomain/zero/1.0/">CC0</a>, <a href="https://commons.wikimedia.org/wiki/File:WebAssembly_Logo.svg">via Wikimedia Commons</a>
