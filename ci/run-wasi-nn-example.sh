#!/bin/bash

# The following script demonstrates how to execute a machine learning inference
# using the wasi-nn module optionally compiled into Wasmtime. Calling it will
# download the necessary model and tensor files stored separately in $FIXTURE
# into $TMP_DIR (optionally pass a directory with existing files as the first
# argument to re-try the script). Then, it will compile and run several examples
# in the Wasmtime CLI.
set -e
WASMTIME_DIR=$(dirname "$0" | xargs dirname)
FIXTURE=https://github.com/intel/openvino-rs/raw/main/crates/openvino/tests/fixtures/mobilenet
if [ -z "${1+x}" ]; then
    # If no temporary directory is specified, create one.
    TMP_DIR=$(mktemp -d -t ci-XXXXXXXXXX)
    REMOVE_TMP_DIR=1
else
    # If a directory was specified, use it and avoid removing it.
    TMP_DIR=$(realpath $1)
    REMOVE_TMP_DIR=0
fi

# One of the examples expects to be in a specifically-named directory.
mkdir -p $TMP_DIR/mobilenet
TMP_DIR=$TMP_DIR/mobilenet

# Build Wasmtime with wasi-nn enabled; we attempt this first to avoid extra work
# if the build fails.
cargo build -p wasmtime-cli --features wasi-nn

# Download all necessary test fixtures to the temporary directory.
wget --no-clobber $FIXTURE/mobilenet.bin --output-document=$TMP_DIR/model.bin
wget --no-clobber $FIXTURE/mobilenet.xml --output-document=$TMP_DIR/model.xml
wget --no-clobber $FIXTURE/tensor-1x224x224x3-f32.bgr --output-document=$TMP_DIR/tensor.bgr

# Now build an example that uses the wasi-nn API. Run the example in Wasmtime
# (note that the example uses `fixture` as the expected location of the
# model/tensor files).
pushd $WASMTIME_DIR/crates/wasi-nn/examples/classification-example
cargo build --release --target=wasm32-wasi
cp target/wasm32-wasi/release/wasi-nn-example.wasm $TMP_DIR
popd
cargo run -- run --mapdir fixture::$TMP_DIR \
    --wasi-modules=experimental-wasi-nn $TMP_DIR/wasi-nn-example.wasm

# Build and run another example, this time using Wasmtime's graph flag to
# preload the model.
pushd $WASMTIME_DIR/crates/wasi-nn/examples/classification-example-named
cargo build --release --target=wasm32-wasi
cp target/wasm32-wasi/release/wasi-nn-example-named.wasm $TMP_DIR
popd
cargo run -- run --mapdir fixture::$TMP_DIR --wasi-nn-graph openvino::$TMP_DIR \
    --wasi-modules=experimental-wasi-nn $TMP_DIR/wasi-nn-example-named.wasm

# Clean up the temporary directory only if it was not specified (users may want
# to keep the directory around).
if [[ $REMOVE_TMP_DIR -eq 1 ]]; then
    rm -rf $TMP_DIR
fi
