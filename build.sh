#!/bin/bash

cd `dirname $0`

if [ ! -d build ]; then
    mkdir build
fi

cd build

if [ -z "$CC" ]; then
    export CC=clang++
fi

$CC --version

# env | sort

if [ -z "$TRAVIS_BRANCH" ]; then
    export TRAVIS_BRANCH=`git branch | grep \* | cut -d ' ' -f2`
fi

if [ ! -d stlab ]; then
    echo "Cloning stlab/$TRAVIS_BRANCH..."

    git clone --branch $TRAVIS_BRANCH --depth=1 https://github.com/stlab/libraries.git stlab
else
    echo "Found stlab. Pulling $TRAVIS_BRANCH..."

    cd stlab
    git branch -u origin/$TRAVIS_BRANCH
    git co $TRAVIS_BRANCH
    git pull origin $TRAVIS_BRANCH
    cd ..
fi

if [ ! -d boost ]; then
    if [ ! -f boost.tgz ]; then
        echo "Downloading boost..."
        curl -L https://downloads.sourceforge.net/project/boost/boost/1.60.0/boost_1_60_0.tar.gz -o boost.tgz
    fi

    if [ ! -d boost ]; then
        mkdir boost
    fi

    echo "Unpacking boost headers..."
    tar -C boost -xzf boost.tgz --strip-components 1 boost_1_60_0/boost/

    echo "Unpacking boost sources..."
    tar -C boost -xzf boost.tgz --strip-components 1 boost_1_60_0/libs/
else
    echo "Found boost..."
fi

if [ ! -d bin ]; then
    mkdir bin
fi

cd ..

find ./libraries -name "*.cpp" | while read -r src
do
  export CMD="$CC -Wall -Werror -x c++ -std=c++14  -I./build/stlab -I./build/boost -o ./build/a.out $src"
  echo $CMD
  $CMD

  export RETVAL=$?
  if [ "$RETVAL" != "0" ]; then
    exit "$RETVAL"
  fi

  ./build/a.out > /dev/null

  export RETVAL=$?
  if [ "$RETVAL" != "0" ]; then
    echo "Error: execution failure."
    exit "$RETVAL"
  fi
done
