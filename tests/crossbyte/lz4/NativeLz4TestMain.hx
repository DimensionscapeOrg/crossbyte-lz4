package crossbyte.lz4;

class NativeLz4TestMain {
	public static function main():Void {
		crossbyte.test.TestHarness.run(runner -> runner.addCase(new NativeLz4Test()));
	}
}
