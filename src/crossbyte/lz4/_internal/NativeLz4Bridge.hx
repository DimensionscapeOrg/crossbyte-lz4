package crossbyte.lz4._internal;

#if (cpp && crossbyte_lz4_native)
@:buildXml("
<files id='haxe'>
	<compilerflag value='-I${haxelib:crossbyte-lz4}/native'/>
	<compilerflag value='-I${haxelib:crossbyte-lz4}/native/vendor/lz4'/>
	<file name='${haxelib:crossbyte-lz4}/native/NativeLz4.cpp'>
		<depend name='${haxelib:crossbyte-lz4}/native/NativeLz4.h'/>
	</file>
	<file name='${haxelib:crossbyte-lz4}/native/vendor/lz4/lz4.c'/>
</files>
")
@:include("NativeLz4.h")
extern class NativeLz4Bridge {
	@:native("crossbyte_lz4_available") public static function isAvailable():Bool;
	@:native("crossbyte_lz4_version") public static function version():String;
	@:native("crossbyte_lz4_compress") public static function compress(input:haxe.io.BytesData, inputLength:Int):haxe.io.BytesData;
	@:native("crossbyte_lz4_decompress") public static function decompress(input:haxe.io.BytesData, inputLength:Int, maxOutputSize:Int):haxe.io.BytesData;
}
#else
extern class NativeLz4Bridge {}
#end
