name: Build iOS Dylib

on:
  push:
    branches: [ main, master ]
  workflow_dispatch: 

jobs:
  build:
    runs-on: macos-latest
    steps:
      - name: Lay ma nguon
        uses: actions/checkout@v4

      - name: Cai dat Theos
        run: |
          bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
          echo "THEOS=~/theos" >> $GITHUB_ENV

      - name: Tu dong tai thư vien Dobby ve de compile
        run: |
          mkdir -p ~/theos/lib
          curl -L -o ~/theos/lib/libdobby.dylib "https://github.com/jmpews/Dobby/releases/download/v1.2.3/libdobby.dylib" || true
          # Dong thoi tao 1 bản sao trong thu muc dự an de đóng gói
          mkdir -p Frameworks
          curl -L -o Frameworks/libdobby.dylib "https://github.com/jmpews/Dobby/releases/download/v1.2.3/libdobby.dylib" || true

      - name: Build file Dylib
        run: |
          make
          
      - name: Xuat file thanh pham
        uses: actions/upload-artifact@v4
        with:
          name: HaiCuong_ModMenu_Dylib
          path: .theos/obj/debug/*.dylib
