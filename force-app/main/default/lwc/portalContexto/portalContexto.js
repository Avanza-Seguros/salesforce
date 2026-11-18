/**
 * @creation date: 18/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Contexto del sitio de empresas para los componentes de Salesforce que se muestran en él
 * (movimientosColectivo, movimientosFlotilla, movimientosUbicaciones, participantesPoliza y los que abren:
 * endosos, carga del archivo, otras pólizas). En el sitio cada llamada a Apex pasa por
 * PortalPolizasMovimientos.ejecutar, que valida que la póliza sea del usuario y que sea el contratante; en Salesforce
 * se llama al método original.
 */
import ejecutar from '@salesforce/apex/PortalPolizasMovimientos.ejecutar';

const contexto = { portal: false, policyId: null, cuentaVistaPrevia: null };

/**
 * Marca que los componentes se muestran en el sitio para la póliza indicada.
 * @param policyId: Id de la póliza abierta en el sitio
 * @param cuentaVistaPrevia: Cuenta simulada (vista previa de administrador) o null
 */
export function fijarPortal(policyId, cuentaVistaPrevia) {
    contexto.portal = true;
    contexto.policyId = policyId || null;
    contexto.cuentaVistaPrevia = cuentaVistaPrevia || null;
}

/** true si los componentes están en el sitio. */
export function enPortal() {
    return contexto.portal;
}

/**
 * Descarga en el sitio un documento de la póliza o de uno de sus endosos (el usuario del sitio no tiene acceso
 * directo a los archivos).
 * @param documentId: Id del ContentDocument
 * @param contenedor: Elemento del componente donde se agrega el enlace temporal de descarga
 */
export async function descargarDocumento(documentId, contenedor) {
    const archivo = await llamar('Documento.descargar', { documentId }, null);
    const bytes = Uint8Array.from(atob(archivo.base64), (c) => c.charCodeAt(0));
    const url = URL.createObjectURL(new Blob([bytes], { type: archivo.mime || 'application/octet-stream' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = archivo.nombre;
    contenedor.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
}

/**
 * Llama a Apex: en Salesforce el método original; en el sitio, la acción equivalente validada.
 * @param accion: Nombre de la acción (Clase.metodo) que entiende PortalPolizasMovimientos
 * @param params: Parámetros (los mismos nombres que el método original)
 * @param original: Método de Apex importado
 * @return Promise con el resultado del método
 */
export function llamar(accion, params, original) {
    if (!contexto.portal) {
        return original(params);
    }
    return ejecutar({
        policyId: contexto.policyId,
        cuentaVistaPrevia: contexto.cuentaVistaPrevia,
        accion,
        parametros: JSON.stringify(params || {})
    });
}
