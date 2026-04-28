package crossbyte.lz4;

import crossbyte.io.ByteArray;
import crossbyte.utils.CompressionAlgorithm;
import haxe.io.Bytes;
import utest.Assert;

class NativeLz4Test extends utest.Test {
	public function testAvailabilityMatchesBuildDefine():Void {
		#if (cpp && crossbyte_lz4_native)
		Assert.isTrue(NativeLz4.isAvailable());
		Assert.notEquals("unavailable", NativeLz4.version());
		#else
		Assert.isFalse(NativeLz4.isAvailable());
		Assert.equals("unavailable", NativeLz4.version());
		#end
	}

	#if (cpp && crossbyte_lz4_native)
	public function testNativeRoundTrip():Void {
		var input = Bytes.ofString("hello native lz4 hello native lz4");
		var compressed = NativeLz4.compress(input);
		var decompressed = NativeLz4.decompress(compressed);

		Assert.equals(input.toString(), decompressed.toString());
	}

	public function testCoreAndNativeCanDecodeEachOther():Void {
		var input = Bytes.ofString("lz4 oracle parity payload");
		var coreEncoded:ByteArray = ByteArray.fromBytes(input);
		coreEncoded.compress(CompressionAlgorithm.LZ4);
		Assert.equals(input.toString(), NativeLz4.decompress(coreEncoded).toString());

		var nativeEncoded = NativeLz4.compress(input);
		var coreDecoded:ByteArray = ByteArray.fromBytes(nativeEncoded);
		coreDecoded.uncompress(CompressionAlgorithm.LZ4);
		Assert.equals(input.toString(), coreDecoded.toString());
	}

	public function testNativeRejectsInvalidPayload():Void {
		var encoded = NativeLz4.compress(Bytes.ofString("this payload will be truncated"));
		var truncated = encoded.sub(0, encoded.length - 1);
		Assert.raises(() -> NativeLz4.decompress(truncated));
	}

	public function testEmptyPayloadParity():Void {
		var empty = Bytes.alloc(0);
		var encoded = NativeLz4.compress(empty);
		Assert.equals(1, encoded.length);
		Assert.equals(0, encoded.get(0));
		Assert.equals(0, NativeLz4.decompress(encoded).length);
	}
	#end
}
