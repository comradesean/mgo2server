package nomad.common;

import org.jdbi.v3.core.statement.Update;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

public class DbUtil {
	public static void addOptional(Update update, Object... kvs) {
		var keys = new ArrayList<String>();
		var values = new ArrayList<>();
		for (int i = 0; i < kvs.length / 2; i++) {
			var k = kvs[i * 2];
			var v = kvs[i * 2 + 1];
			if (k instanceof String s && v != null) {
				keys.add(s);
				values.add(v);
			}
		}

		if (keys.isEmpty()) {
			return;
		}

		update.defineList("keys", ", " + String.join(", ", keys));
		update.define("values", ", :__values2_0");
		update.bindList("values2", values);
	}
}
