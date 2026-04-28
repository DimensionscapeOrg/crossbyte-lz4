import crossbyte.lz4.NativeLz4Test;

class TestMain {
	public static function main():Void {
		crossbyte.test.TestHarness.run(runner -> runner.addCase(new NativeLz4Test()));
	}
}
