/**
 * @creation date: 14/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de JsonIa (reparación del JSON que devuelve la IA).
 */
@isTest
private class JsonIaTest {

	/**
	 * @description: Un salto de renglón dentro de un texto se cambia por espacio y el JSON ya se puede leer;
	 *               lo que está fuera de las cadenas y las comillas escapadas no se tocan.
	 */
	@isTest
	static void testSaltoDentroDeTexto() {
		String comilla = String.fromCharArray(new List<Integer>{ 92, 34 }); // comilla escapada dentro del texto
		String roto = '{\n  "nombre": "SECCIÓN BIENES\nTodo Riesgo ' + comilla + 'Incendio' + comilla + '",\n  "suma": 10\n}';
		String ok = JsonIa.repararTextos(roto);
		Map<String, Object> d = (Map<String, Object>) JSON.deserializeUntyped(ok);
		System.assertEquals('SECCIÓN BIENES Todo Riesgo "Incendio"', d.get('nombre'), 'Salto cambiado por espacio');
		System.assertEquals(10, d.get('suma'), 'Lo de fuera de las cadenas no cambia');
		System.assert(ok.startsWith('{\n'), 'Los saltos fuera de las cadenas se conservan');
		System.assertEquals('{"a":1}', JsonIa.repararTextos('{"a":1}'), 'Un JSON válido no cambia');
		System.assertEquals(null, JsonIa.repararTextos(null), 'Vacío');
	}
}
