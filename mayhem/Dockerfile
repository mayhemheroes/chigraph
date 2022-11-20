FROM --platform=linux/amd64 ubuntu:22.04 as builder
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake ninja-build llvm-12-dev libssl-dev clang-12               libboost-dev liblldb-12-dev clang
COPY . /repo
WORKDIR /repo/build
ENV LLVM_VERSION=12
RUN cmake .. -DCMAKE_CXX_COMPILER=clang++     -DCMAKE_C_COMPILER=clang     -GNinja -DCMAKE_CXX_FLAGS='--coverage'     -DLLVM_CONFIG="/usr/lib/llvm-${LLVM_VERSION}/bin/llvm-config" -DCMAKE_INSTALL_PREFIX=/install
RUN ninja install
RUN clang++ /repo/mayhem/fuzz_unmangleFunctionName.cpp -fsanitize=fuzzer,address -I /install/include/ -L /install/lib/ -lchigraphcore --coverage -o /fuzz_unmangleFunctionName
WORKDIR /repo/build/bin
RUN ./chi init
