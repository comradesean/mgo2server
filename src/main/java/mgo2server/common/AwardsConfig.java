package mgo2server.common;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Set;

/**
 * The award requirements, read from {@code awards.json} on the classpath.
 *
 * <h2>Why this is a file and not code</h2>
 * <b>Title thresholds are invented by us.</b> Nothing in the game states one — the client's own
 * descriptions name the statistic ("High kill count") and never the number, and no threshold table
 * exists in the binary. The values we ship come from a community list for a late version of MGO2,
 * adapted to the 22 titles this disc carries, with gaps filled by best guess. They are expected to
 * be wrong in places and to need repeated tuning, which is exactly the case for keeping them in a
 * file an operator can edit rather than constants only a rebuild can reach.
 * <p>
 * <b>Medal thresholds are not a free choice</b>, and are here only so both live together: the value
 * is the number the client prints in that medal's own caption, so awarding at exactly that number is
 * what makes the screen truthful. Changing one makes the client state a requirement we did not
 * apply.
 *
 * <h2>Failure behaviour</h2>
 * Every problem is fatal at startup and names the offending entry. This follows {@link Policy}'s
 * reasoning rather than the softer fallback some probe readers use: a malformed requirement cannot
 * be defaulted sensibly, and silently dropping one would grant or withhold awards for a reason
 * nobody could see. A server that will not start is a bug report; one that quietly awards nothing
 * is not.
 */
public record AwardsConfig(List<Title> titles, List<Medal> medals) {

	/** The highest bit the client can render. Bit 22+ corrupts its scrollbar — see V45. */
	public static final int MAX_TITLE_BIT = 21;

	/** Where the shipped requirements live. */
	public static final String RESOURCE = "awards.json";

	private static final AwardsConfig CURRENT = load(RESOURCE);

	/** The process-wide requirements, read once at class initialisation. */
	public static AwardsConfig current() {
		return CURRENT;
	}

	/**
	 * One title and every clause a character must satisfy to unlock it.
	 *
	 * @param bit position in the 22-bit mask at {@code 0x4103} wire 563
	 * @param rank display precedence — the LOWEST rank among unlocked titles is the one worn
	 */
	public record Title(String name, int bit, int rank, String description, List<Clause> requires) {
	}

	/**
	 * One medal tier.
	 *
	 * @param byteIndex which of the 16 bytes at {@code 0x4103} wire 615 carries it
	 * @param slot the {@code 0x4107} slot, when {@code metric} is {@code slot}
	 */
	public record Medal(int id, int byteIndex, int bit, AwardMetric metric, int slot, long value,
			String caption) {
	}

	/**
	 * One requirement. {@code modes} narrows the statistic to those game rules; empty means every
	 * mode.
	 */
	public record Clause(AwardMetric metric, Set<String> modes, Op op, double value) {

		/** Whether a computed metric satisfies this clause. */
		public boolean test(double actual) {
			return op.test(actual, value);
		}
	}

	/** The comparisons a clause may use. */
	public enum Op {
		AT_LEAST(">="), GREATER(">"), AT_MOST("<="), LESS("<");

		private final String symbol;

		Op(String symbol) {
			this.symbol = symbol;
		}

		static Op of(String symbol, String where) {
			for (var op : values()) {
				if (op.symbol.equals(symbol)) {
					return op;
				}
			}
			throw new IllegalArgumentException(where + ": unknown operator \"" + symbol
				+ "\"; expected one of >=, >, <=, <");
		}

		boolean test(double actual, double threshold) {
			return switch (this) {
				case AT_LEAST -> actual >= threshold;
				case GREATER -> actual > threshold;
				case AT_MOST -> actual <= threshold;
				case LESS -> actual < threshold;
			};
		}
	}

	/**
	 * Reads and validates a requirements resource. Package-visible on purpose so tests can point it
	 * at a deliberately broken file, the same seam {@link Policy#from} provides.
	 */
	public static AwardsConfig load(String resource) {
		try (var stream = AwardsConfig.class.getClassLoader().getResourceAsStream(resource)) {
			Objects.requireNonNull(stream, () -> "Missing award requirements resource: " + resource);
			return parse(new ObjectMapper().readTree(stream), resource);
		}
		catch (IOException e) {
			throw new UncheckedIOException("Failed to read award requirements: " + resource, e);
		}
	}

	private static AwardsConfig parse(JsonNode root, String where) {
		var titles = new ArrayList<Title>();
		var seenBits = new java.util.HashSet<Integer>();
		for (var node : root.path("titles")) {
			var name = node.path("name").asText("(unnamed)");
			var at = where + " title \"" + name + "\"";
			var bit = node.path("bit").asInt(-1);
			if (bit < 0 || bit > MAX_TITLE_BIT) {
				throw new IllegalArgumentException(at + ": bit must be 0.." + MAX_TITLE_BIT
					+ ", got " + bit + ". Bit 22 and above corrupt the client's title screen.");
			}
			if (!seenBits.add(bit)) {
				throw new IllegalArgumentException(at + ": bit " + bit + " is already used by "
					+ "another title; two titles cannot share a bit.");
			}
			var clauses = new ArrayList<Clause>();
			for (var clause : node.path("requires")) {
				clauses.add(clause(clause, at));
			}
			if (clauses.isEmpty()) {
				throw new IllegalArgumentException(at + ": has no requirements, so every character "
					+ "would unlock it. Give it a clause or remove it.");
			}
			titles.add(new Title(name, bit, node.path("rank").asInt(Integer.MAX_VALUE),
				node.path("description").asText(""), List.copyOf(clauses)));
		}

		var medals = new ArrayList<Medal>();
		for (var node : root.path("medals")) {
			var id = node.path("id").asInt(-1);
			var at = where + " medal " + id;
			var byteIndex = node.path("byte").asInt(-1);
			var bit = node.path("bit").asInt(-1);
			if (byteIndex < 0 || byteIndex > 15 || bit < 0 || bit > 7) {
				throw new IllegalArgumentException(at + ": byte must be 0..15 and bit 0..7, got "
					+ byteIndex + "." + bit);
			}
			medals.add(new Medal(id, byteIndex, bit, metric(node, at), node.path("slot").asInt(0),
				node.path("value").asLong(), node.path("caption").asText("")));
		}

		if (titles.isEmpty() && medals.isEmpty()) {
			throw new IllegalArgumentException(where + ": defines no titles and no medals; a typo "
				+ "in the top-level keys would look exactly like this.");
		}
		return new AwardsConfig(List.copyOf(titles), List.copyOf(medals));
	}

	private static Clause clause(JsonNode node, String at) {
		var modes = new java.util.LinkedHashSet<String>();
		for (var mode : node.path("modes")) {
			modes.add(mode.asText());
		}
		return new Clause(metric(node, at), Set.copyOf(modes),
			Op.of(node.path("op").asText(">="), at), node.path("value").asDouble());
	}

	private static AwardMetric metric(JsonNode node, String at) {
		var name = node.path("metric").asText("");
		try {
			return AwardMetric.valueOf(name.toUpperCase(java.util.Locale.ROOT));
		}
		catch (IllegalArgumentException e) {
			throw new IllegalArgumentException(at + ": unknown metric \"" + name + "\". The set is "
				+ "fixed in AwardMetric; this file chooses among them and cannot define new ones.");
		}
	}
}
