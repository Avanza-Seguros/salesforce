/**
 * @creation date: 14/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Reparaciones del JSON que devuelve la IA antes de deserializarlo. El modelo a veces copia el salto
 *               de renglón del PDF dentro de un texto (ej. el nombre de una cobertura que ocupa dos renglones) y un
 *               JSON no admite caracteres de control sin escapar dentro de una cadena: falla al leerlo.
 */
public inherited sharing class JsonIa {

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cambia por un espacio los caracteres de control (salto de renglón, tabulador...) que vienen sin
	 *               escapar DENTRO de las cadenas del JSON. Fuera de las cadenas no se toca nada.
	 * @param json: JSON devuelto por la IA.
	 * @return el mismo JSON con las cadenas reparadas.
	 */
	public static String repararTextos(String json) {
		if (String.isBlank(json)) { return json; }
		// Se arma con substring (String.fromCharArray pierde las diagonales invertidas de los escapes).
		List<String> partes = new List<String>();
		Integer desde = 0;
		Boolean enCadena = false;
		Boolean escapado = false;
		for (Integer i = 0; i < json.length(); i++) {
			Integer c = json.charAt(i);
			if (!enCadena) {
				if (c == 34) { enCadena = true; }
				continue;
			}
			if (escapado) {
				escapado = false;
			} else if (c == 92) {
				escapado = true;
			} else if (c == 34) {
				enCadena = false;
			} else if (c < 32) {
				partes.add(json.substring(desde, i));
				partes.add(' ');
				desde = i + 1;
			}
		}
		if (partes.isEmpty()) { return json; }
		partes.add(json.substring(desde));
		return String.join(partes, '');
	}
}
