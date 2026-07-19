package nomad;

import io.netty.buffer.ByteBufUtil;
import io.netty.buffer.Unpooled;
import org.assertj.core.api.AbstractAssert;

import java.util.Arrays;

public class BytesAssert extends AbstractAssert<BytesAssert, Bytes> {
	public BytesAssert(Bytes actual) {
		super(actual, BytesAssert.class);
	}

	public static BytesAssert assertThat(Bytes actual) {
		return new BytesAssert(actual);
	}

	public BytesAssert isEqualTo(Bytes expected) {
		isNotNull();

		if (!Arrays.equals(expected.getBytes(), actual.getBytes())) {
			var expectedDump = ByteBufUtil.hexDump(Unpooled.wrappedBuffer(expected.getBytes()));
			var actualDump = ByteBufUtil.hexDump(Unpooled.wrappedBuffer(actual.getBytes()));
			failWithMessage("\nExpected:\n%s\nbut was:\n%s", expectedDump, actualDump);
		}

		return this;
	}
}
