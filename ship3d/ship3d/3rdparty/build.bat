cd ./DerelictSDL2-master
rd /s /q lib 
dub build --build=release
cd ../DerelictUtil-master
rd /s /q lib 
dub build --build=release
pause