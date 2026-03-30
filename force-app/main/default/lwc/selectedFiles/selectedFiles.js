import { LightningElement, api, track, wire } from 'lwc';
import {NavigationMixin} from 'lightning/navigation';
import getFiles from '@salesforce/apex/GetFilesSelected.getFiles';
import getNormalFiles from '@salesforce/apex/GetFilesSelected.getNormalFiles';
import UpdateFile from '@salesforce/apex/GetFilesSelected.UpdateFile';


export default class SelectedFiles extends NavigationMixin(LightningElement) {

    @api recordId;
    @track filesList = [];
    @track filesListNormal = [];
    
    @wire(getFiles, {IdRecord: "$recordId"})
    getDataSelectedFiles({data, error}){ 
        if(data){
            console.log('selected '+data);
            this.filesList = Object.keys(data).map(item=>({
                "label": data[item].Title,
                "value": item,
                "Id": data[item].Id,
                "ContentDocumentId": data[item].ContentDocumentId,
                "Extension": data[item].FileExtension,
                "Date": data[item].ContentModifiedDate,
                "ModifiedBy": data[item].ContentModifiedBy.Name

            }));
        }
    }

    @wire(getNormalFiles, {IdRecord: "$recordId"})
    getDataNormalFiles({data, error}){ 
        if(data){
            console.log('normal '+data);
            this.filesListNormal = Object.keys(data).map(item=>({
                "label": data[item].Title,
                "value": item,
                "Id": data[item].Id,
                "ContentDocumentId": data[item].ContentDocumentId,
                "Extension": data[item].FileExtension,
                "Date": data[item].ContentModifiedDate,
                "ModifiedBy": data[item].ContentModifiedBy.Name

            }));
        }
    }

    reloadPage(event){
        let uploadedFiles = event.detail.files;
        for(var i=0; i <= uploadedFiles.length; i++){
            UpdateFile({IdRecord: uploadedFiles[i].documentId})
            .then((data) => {
                console.log('Success ');
                window.location.reload();
            })
            //.catch((error) => {
                //window.location.reload();
            //    alert('Error al vincular el archivo '+this.error);
           // });
        }
        
    }

    reloadPageNormalFiles(event){
        window.location.reload();
    }

    viewRecord(event){
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state:{
                selectedRecordId: event.target.dataset.id
            }
        });
    }

}