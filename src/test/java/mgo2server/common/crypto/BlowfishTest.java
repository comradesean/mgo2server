package mgo2server.common.crypto;

import io.netty.buffer.Unpooled;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import java.util.HexFormat;

import static org.assertj.core.api.Assertions.*;

/**
 * Known-answer tests for the MGO2 Blowfish variant.
 * <p>
 * <b>Evidence: regression guard, not a correctness check.</b> The expected values were produced by
 * running Nomad's {@code savemgo.nomad.crypto.Crypto} over these inputs, so they prove only that
 * this rewrite matches <em>that</em> implementation. What actually proves the algorithm is
 * production: a real client's encrypted payloads decrypt with {@code packet.key} and it accepts
 * ours in return. These vectors exist to catch silent drift, and would not catch both
 * implementations being wrong together.
 */
public class BlowfishTest {
	private static final HexFormat HEX = HexFormat.of();

	// plaintext, packet-key encrypt, packet-key decrypt
	@ParameterizedTest(name = "{0} bytes")
	@CsvSource({
		"344b5b2e116ee87a,"
			+ "67fc5890077915b7,e926129be2ce9225",

		"8cb3662a7a5f622f016e848962d3a078,"
			+ "6f95660ee1652aedcdf9526c4371ab32,cd31fd54a963fc64d99a2f3fdf03bbc7",

		"e51b7125e34fdbe55d2ea1b51e0bf40545c94f7c6e47d423,"
			+ "1595f0d6807949bec3e33fc86b3cb5f1443d594b7ce63393,"
			+ "3158c878621fcd6c08501ec5a1f6e632a00d7372cc674825",

		"9e25a80df2023b7126f1318fcb259cc8d3c65c73586e3a4cebcfd505ee1a5a4455066d05ad171f7882cd71f7d1d50c09cb1fb04619faaed8ddfbe72b3293e527,"
			+ "7bd09bb7c1f5f4ad0c756b6c70009394227f60fd0bd5303ad562d4558c754e62d7d19dddb71400c1101a21e1b6e2be76316120a5f99605654bc68e833fb2135a,"
			+ "2acd7fc75e756a7f66e5ba4271fb33cf286c00ef2341f9332509e2cfc38efa88612843d9260966cc3497d964cc8a23e7199cff1b3b5c77f92ea5948fcb7f7ba4",
	})
	public void matchesOriginalImplementation(
		String plainHex, String packetEncrypted, String packetDecrypted
	) {
		var plain = HEX.parseHex(plainHex);

		assertThat(apply(GameCrypto.packet(), plain, true)).isEqualTo(packetEncrypted);
		assertThat(apply(GameCrypto.packet(), plain, false)).isEqualTo(packetDecrypted);
	}

	private static String apply(Blowfish cipher, byte[] plain, boolean encrypt) {
		var data = plain.clone();
		if (encrypt) {
			cipher.encrypt(data);
		} else {
			cipher.decrypt(data);
		}
		return HEX.formatHex(data);
	}

	@Test
	public void encryptThenDecryptRoundTrips() {
		var plain = HEX.parseHex("0011223344556677889900aabbccddee");

		var data = plain.clone();
		GameCrypto.packet().encrypt(data);
		assertThat(data).isNotEqualTo(plain);

		GameCrypto.packet().decrypt(data);
		assertThat(data).isEqualTo(plain);
	}

	@Test
	public void byteBufAndArrayPathsAgree() {
		var plain = HEX.parseHex("0011223344556677889900aabbccddee");

		var expected = plain.clone();
		GameCrypto.packet().encrypt(expected);

		var buffer = Unpooled.buffer(plain.length);
		buffer.writeBytes(plain);
		GameCrypto.packet().encrypt(buffer);

		var actual = new byte[plain.length];
		buffer.getBytes(0, actual);
		assertThat(actual).isEqualTo(expected);
	}

	@Test
	public void keySchedulesAreDistinct() {
		var plain = HEX.parseHex("0011223344556677");

		var viaPacket = plain.clone();
		GameCrypto.packet().encrypt(viaPacket);

		var viaSession = plain.clone();
		Blowfish.loadResource("crypto/session.key").encrypt(viaSession);

		assertThat(viaPacket).isNotEqualTo(viaSession);
	}

	@Test
	public void rejectsPartialBlocks() {
		assertThatThrownBy(() -> GameCrypto.packet().encrypt(new byte[7]))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("multiple of 8");
	}

	@Test
	public void rejectsWrongSizedKeySchedule() {
		assertThatThrownBy(() -> Blowfish.load(new byte[128]))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("4168");
	}
}
