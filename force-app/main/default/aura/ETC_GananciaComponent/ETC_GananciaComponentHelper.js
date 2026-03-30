({
    getGananciaActual : function(component) {
        return new Promise(
            $A.getCallback(function(resolve, reject) {
                try {
                    console.log('getGananciaActual');
                    var recordId = component.get('v.recordId');
                    console.log(recordId+'recordId');
                    var action = component.get("c.getGananciaActual");
                    
                    action.setCallback(this, function(response) {
                        if(response.getState() === 'SUCCESS') {
                            try {
                                console.log('EXITOSO getDescuentos');
                                var result = response.getReturnValue();
                                console.log(result);
                                resolve(result != null? result:0);
                            } catch (error) {
                                console.log(error);
                                reject(error);
                                // this.showToast('error','Mensaje',error);
                            }
                        }else{
                            console.log(response.getState());
                            console.log(response.getError());
                            // this.showToast('error','Mensaje',response.getError());
                            reject(JSON.stringify(response.getError()));
                        }
                        
                    });
                    $A.enqueueAction(action); 
                } catch (error) {
                    console.log(error);
                    reject(error);
                }
            })
        );
    },
    getGananciaAnterior : function(component) {
        return new Promise(
            $A.getCallback(function(resolve, reject) {
                try {
                    console.log('getGananciaAnterior');
                    var recordId = component.get('v.recordId');
                    console.log(recordId+'recordId');
                    var action = component.get("c.getGananciaAnterior");
                    
                    action.setCallback(this, function(response) {
                        if(response.getState() === 'SUCCESS') {
                            try {
                                console.log('EXITOSO getDescuentos');
                                var result = response.getReturnValue();
                                console.log(result);
                                resolve(result != null? result:0);
                            } catch (error) {
                                console.log(error);
                                reject(error);
                                // this.showToast('error','Mensaje',error);
                            }
                        }else{
                            console.log(response.getState());
                            console.log(response.getError());
                            // this.showToast('error','Mensaje',response.getError());
                            reject(JSON.stringify(response.getError()));
                        }
                        
                    });
                    $A.enqueueAction(action); 
                } catch (error) {
                    console.log(error);
                    reject(error);
                }
            })
        );
    },
    
})