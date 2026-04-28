package crossbyte.lz4;

import crossbyte.lz4._internal.NativeLz4Bridge;
import haxe.io.Bytes;

class NativeLz4 {
	private static final __empty:Bytes = Bytes.alloc(0);

	public static inline function isAvailable():Bool {
		#if (cpp && crossbyte_lz4_native)
		return NativeLz4Bridge.isAvailable();
		#else
		return false;
		#end
	}

	public static inline function version():String {
		#if (cpp && crossbyte_lz4_native)
		return NativeLz4Bridge.version();
		#else
		return "unavailable";
		#end
	}

	public static function compress(bytes:Bytes):Bytes {
		#if (cpp && crossbyte_lz4_native)
		var input = bytes == null ? __empty : bytes;
		return Bytes.ofData(NativeLz4Bridge.compress(input.getData(), input.length));
		#else
		throw "Native LZ4 is only available on cpp targets with -D crossbyte_lz4_native.";
		#end
	}

	public static function decompress(bytes:Bytes):Bytes {
		#if (cpp && crossbyte_lz4_native)
		var input = bytes == null ? __empty : bytes;
		return Bytes.ofData(NativeLz4Bridge.decompress(input.getData(), input.length));
		#else
		throw "Native LZ4 is only available on cpp targets with -D crossbyte_lz4_native.";
		#end
	}
}
