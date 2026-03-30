({
    downloadAttachments: function(component, event, helper) {
        var recordId = component.get("v.recordId");
        var action = component.get("c.getAttachmentUrls");
        
        action.setParams({ recordId: recordId });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var attachmentUrls = response.getReturnValue();
                console.log(attachmentUrls);
                for (let i = 0; i < attachmentUrls.length; i++) {
                    var urlEvent = $A.get("e.force:navigateToURL");
                    urlEvent.setParams({
                        "url": attachmentUrls[i]
                    });
                    urlEvent.fire();
                }
            } else {
                alert('Error al obtener los archivos adjuntos.');
            }
        });
        
        $A.enqueueAction(action);
    },
})