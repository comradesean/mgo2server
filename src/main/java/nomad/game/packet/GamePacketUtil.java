package nomad.game.packet;

import io.netty.buffer.ByteBuf;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;

public class GamePacketUtil {
	private static final String HMAC_MD5 = "HmacMD5";

	private static final SecretKeySpec CHECKSUM_KEY = new SecretKeySpec(new byte[] { (byte) 0x5A, (byte) 0x37, (byte) 0x2F, (byte) 0x62, (byte) 0x69, (byte) 0x4A, (byte) 0x34, (byte) 0x36, (byte) 0x54, (byte) 0x7A, (byte) 0x47, (byte) 0x46, (byte) 0x2D, (byte) 0x38, (byte) 0x79, (byte) 0x78 }, HMAC_MD5);

	public void calculateChecksum(ByteBuf buffer) {
		try {
			var mac = Mac.getInstance(HMAC_MD5);
			mac.init(CHECKSUM_KEY);

//			mac.doFinal()
		} catch (NoSuchAlgorithmException | InvalidKeyException e) {
			throw new RuntimeException(e);
		}
	}
}
