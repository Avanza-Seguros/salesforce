// eliminarMovimiento/eliminarMovimiento.js
// Eliminar un registro o toda una solicitud (movimiento) de la póliza, con confirmación. Se usa en
// c-movimientos-colectivo, c-movimientos-flotilla y c-movimientos-ubicaciones, solo en Salesforce.
import LightningConfirm from 'lightning/confirm';
import eliminarMovimiento from '@salesforce/apex/MovimientosColectivoController.eliminarMovimiento';

const numero = (folio) => String(folio || '').replace(/^SOL-/i, '');

/** Se puede eliminar lo de una solicitud (no la carga inicial) que no está Concluido. */
export function sePuedeEliminar(folio, seguimiento) {
    return /^SOL-/i.test(String(folio || '')) && !!seguimiento && seguimiento !== 'Concluido';
}

/**
 * Confirma y elimina un registro.
 * @param p: { policyId, folio, movimientoId, tipo, nombre, conDependientes }
 * @return lo que se hizo, o null si se canceló.
 */
export async function eliminarRegistro(p) {
    const deps = p.conDependientes ? ' y a sus dependientes de este movimiento' : '';
    const que = {
        Alta: `Se elimina el alta y se quita de la póliza a ${p.nombre}${deps}.`,
        Baja: `Se elimina la baja de ${p.nombre}${deps}: vuelve a quedar vigente.`,
        Cambio: `Se elimina el cambio de ${p.nombre}; sus datos se quedan como están.`
    }[p.tipo] || `Se elimina el movimiento de ${p.nombre}.`;
    return confirmar(`${que} No se puede deshacer. ¿Continuar?`, 'Eliminar registro', p);
}

/**
 * Confirma y elimina toda la solicitud.
 * @param p: { policyId, folio, registros }
 * @return lo que se hizo, o null si se canceló.
 */
export async function eliminarSolicitud(p) {
    const n = { Alta: 0, Baja: 0, Cambio: 0 };
    (p.registros || []).forEach((r) => { n[r.tipoMovimiento] = (n[r.tipoMovimiento] || 0) + 1; });
    const partes = [];
    if (n.Alta) { partes.push(`${n.Alta} ${n.Alta === 1 ? 'alta (se quita de la póliza)' : 'altas (se quitan de la póliza)'}`); }
    if (n.Baja) { partes.push(`${n.Baja} ${n.Baja === 1 ? 'baja (vuelve a quedar vigente)' : 'bajas (vuelven a quedar vigentes)'}`); }
    if (n.Cambio) { partes.push(`${n.Cambio} ${n.Cambio === 1 ? 'cambio (los datos se quedan como están)' : 'cambios (los datos se quedan como están)'}`); }
    return confirmar(`Se elimina el movimiento ${numero(p.folio)}${partes.length ? ' con ' + partes.join(', ') : ''}. No se puede deshacer. ¿Continuar?`,
        'Eliminar movimiento', p);
}

async function confirmar(message, label, p) {
    const ok = await LightningConfirm.open({ message, label, variant: 'header', theme: 'error' });
    if (!ok) { return null; }
    return eliminarMovimiento({ policyId: p.policyId, folio: p.folio, movimientoId: p.movimientoId || null });
}
