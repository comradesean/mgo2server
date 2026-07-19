package nomad.common.model;

/**
 * Cosmetic appearance of a character, as chosen in the creation screen.
 * <p>
 * Every value is a small index into the game's own asset tables, so they are stored as-is
 * rather than modelled further.
 */
public class CharaAppearance {
	private long charaId;

	private int gender;

	private int face;

	private int facePaint;

	private int voice;

	private int pitch;

	private int upper;

	private int upperColor;

	private int lower;

	private int lowerColor;

	private int head;

	private int headColor;

	private int chest;

	private int chestColor;

	private int hands;

	private int handsColor;

	private int waist;

	private int waistColor;

	private int feet;

	private int feetColor;

	private int accessory1;

	private int accessory1Color;

	private int accessory2;

	private int accessory2Color;

	public long getCharaId() {
		return charaId;
	}

	public void setCharaId(long charaId) {
		this.charaId = charaId;
	}

	public int getGender() {
		return gender;
	}

	public void setGender(int gender) {
		this.gender = gender;
	}

	public int getFace() {
		return face;
	}

	public void setFace(int face) {
		this.face = face;
	}

	public int getFacePaint() {
		return facePaint;
	}

	public void setFacePaint(int facePaint) {
		this.facePaint = facePaint;
	}

	public int getVoice() {
		return voice;
	}

	public void setVoice(int voice) {
		this.voice = voice;
	}

	public int getPitch() {
		return pitch;
	}

	public void setPitch(int pitch) {
		this.pitch = pitch;
	}

	public int getUpper() {
		return upper;
	}

	public void setUpper(int upper) {
		this.upper = upper;
	}

	public int getUpperColor() {
		return upperColor;
	}

	public void setUpperColor(int upperColor) {
		this.upperColor = upperColor;
	}

	public int getLower() {
		return lower;
	}

	public void setLower(int lower) {
		this.lower = lower;
	}

	public int getLowerColor() {
		return lowerColor;
	}

	public void setLowerColor(int lowerColor) {
		this.lowerColor = lowerColor;
	}

	public int getHead() {
		return head;
	}

	public void setHead(int head) {
		this.head = head;
	}

	public int getHeadColor() {
		return headColor;
	}

	public void setHeadColor(int headColor) {
		this.headColor = headColor;
	}

	public int getChest() {
		return chest;
	}

	public void setChest(int chest) {
		this.chest = chest;
	}

	public int getChestColor() {
		return chestColor;
	}

	public void setChestColor(int chestColor) {
		this.chestColor = chestColor;
	}

	public int getHands() {
		return hands;
	}

	public void setHands(int hands) {
		this.hands = hands;
	}

	public int getHandsColor() {
		return handsColor;
	}

	public void setHandsColor(int handsColor) {
		this.handsColor = handsColor;
	}

	public int getWaist() {
		return waist;
	}

	public void setWaist(int waist) {
		this.waist = waist;
	}

	public int getWaistColor() {
		return waistColor;
	}

	public void setWaistColor(int waistColor) {
		this.waistColor = waistColor;
	}

	public int getFeet() {
		return feet;
	}

	public void setFeet(int feet) {
		this.feet = feet;
	}

	public int getFeetColor() {
		return feetColor;
	}

	public void setFeetColor(int feetColor) {
		this.feetColor = feetColor;
	}

	public int getAccessory1() {
		return accessory1;
	}

	public void setAccessory1(int accessory1) {
		this.accessory1 = accessory1;
	}

	public int getAccessory1Color() {
		return accessory1Color;
	}

	public void setAccessory1Color(int accessory1Color) {
		this.accessory1Color = accessory1Color;
	}

	public int getAccessory2() {
		return accessory2;
	}

	public void setAccessory2(int accessory2) {
		this.accessory2 = accessory2;
	}

	public int getAccessory2Color() {
		return accessory2Color;
	}

	public void setAccessory2Color(int accessory2Color) {
		this.accessory2Color = accessory2Color;
	}

	@Override
	public String toString() {
		return "CharaAppearance{charaId=" + charaId + "}";
	}
}
