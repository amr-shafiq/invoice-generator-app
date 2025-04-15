const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.sendInvoiceNotification = functions.firestore
    .document("invoices/{invoiceId}")
    .onWrite(async (change, context) => {
        const invoiceData = change.after.data();

        if (!invoiceData) return;

        const payload = {
            notification: {
                title: "Invoice Updated",
                body: `Invoice ${invoiceData.id} has been submitted or updated.`,
            },
            topic: "management_notifications", // Notify all management users
        };

        await admin.messaging().send(payload);
        console.log("Notification sent to management.");
    });
