# **Invoice Generation App**

A simple yet powerful application for managing and generating invoices. The app is built using Flutter for cross-platform compatibility, integrated with Supabase for data storage, and Firebase for user authentication. This application is designed to simplify invoice management for your business.

---

## **Table of Contents**
1. [Overview](#overview)
2. [Features](#features)
3. [Installation](#installation)
4. [Usage](#usage)
5. [Technology Stack](#technology-stack)
6. [Contributing](#contributing)
7. [License](#license)

---

## **Overview**

The **Invoice Generation App** is a modern solution that simplifies the process of managing invoices. Whether you're an agent or management, the app allows you to:

- Generate, edit, and track invoices.
- View and manage invoice status (Pending, Reviewed, Paid, etc.).
- Upload and store invoices on Supabase.
- Provide dynamic PDF generation with invoice details like customer name, amount, and booking information.
- Automatically update invoice status based on payments.

---

## **Features**

- **Google Authentication**: Secure login system via Firebase Authentication.
- **Role Management**: Supports different user roles such as agents and management.
- **Dynamic PDF Generation**: Creates and stores invoices with dynamic fields.
- **Supabase Integration**: Store invoices and track data in a secure Supabase database.
- **Invoice Status Tracking**: Automatically assigns invoice statuses like Pending, Reviewed, and Paid.
- **Notifications**: Management is notified when agents submit invoices.
- **Search & Filter**: Easily search and filter invoices by agent, date, and other attributes.
- **Editable Invoices**: Management can review and edit invoices before final approval.
- **Responsive UI**: Designed to work seamlessly on both mobile and tablet devices.

---

## **Installation**

### Prerequisites

Before you begin, make sure you have the following installed:

- **Flutter**: Install Flutter from [flutter.dev](https://flutter.dev).
- **Firebase CLI**: Install Firebase CLI for authentication features.
- **Supabase Account**: Create an account on [Supabase](https://supabase.io) to use their database and storage services.

### Steps to Install

1. **Clone the repository**:
    ```bash
    git clone https://github.com/amr-shafiq/invoice-generator-app.git
    cd invoice-generator-app
    ```

2. **Install dependencies**:
    ```bash
    flutter pub get
    ```

3. **Configure Firebase**:
   - Create a Firebase project in the Firebase console.
   - Enable Firebase Authentication with Google Sign-In.
   - Follow the steps to download the `google-services.json` and place it in your project’s `android/app` folder.

4. **Configure Supabase**:
   - Create a Supabase account and set up a new project.
   - Add your Supabase URL and Anonymous Key to your `.env` file.

    Example `.env` file:
    ```plaintext
    SUPABASE_URL=<your-supabase-url>
    SUPABASE_ANON_KEY=<your-supabase-anon-key>
    ```
5. **Configure Invoice PDF layout**:
   - Once the setup is complete, attach an invoice file (PDF format) into the `assets` folder. Include editable text fields (This project will not work without them!) of the details that needs to be filled up by users. And then edit the property values of each text field once the invoice file has been inserted. Be sure to edit the values as well in these files; `lib/add_pdf_page.dart` and `lib/add_pdf_page_management.dart`.
   - Do note that this project is only used for invoice generation among agents and management used in a travel agency. If this project is used by anything else, then these file may need to be changed entirely (To fit the use case requirement).
   - Change the text field values whenever necessary (If the invoice layout does not match with the default text value as shown in here). It is around the lines like this:
     ```plaintext
     final Map<String, dynamic> fields = {
      "CUSTOMER_NAME": customerName,
      "INVOICE_NO": invoiceNo,
      "DATE": formattedInvoiceDate,
      "BANK_TRANSFER": formattedBankTransfer,
      "HOTEL_NAME": hotel,
      "ROOM_TYPE": roomType,
      "CHECK_IN": formattedCheckInDate,
      "CHECK_OUT": formattedCheckOutDate,
      "ROOM_RATE": roomRate,
      "BREAKFAST_OR_NO": breakfast,
      "QUANTITY": quantityRoom.toString(),
      "BALANCE_DUE": balanceDue.toString(),
      "AMOUNT": amount.toString(),
      "AGENT_NAME": agentName,
      "TOTAL": totalAmount.toString(),
      "PAYMENT": payment.toString(),
      "BALANCE": balance.toString(),
      "BOOKING_NO": bookingNo ?? "Pending Verification",
      "DATELINE": formattedDateline,
      "ADD_ON": addOn,
      "REMARKS": remarks,
    };
     ```

6. **Run the app**:
   - Once the setup is complete, run the app using:
     ```bash
     flutter run
     ```

---

## **Usage**

1. **Sign in**: Sign in with your Google account to start using the app.
2. **Agents**: Upload and manage invoices.
3. **Management**: Review, edit, and approve/reject invoices submitted by agents.
4. **Notifications**: Management will be notified when an agent submits an invoice.
5. **Search and Filter**: Use the search bar and filters to find specific invoices.

---

## **Technology Stack**

- **Frontend**: 
    - **Flutter**: Cross-platform mobile app development.
    - **Provider**: State management solution for handling app states like authentication and invoice data.

- **Backend**: 
    - **Supabase**: Database and file storage service for managing invoices.
    - **Firebase Authentication**: User authentication via Google sign-in.

- **PDF Generation**:
    - **flutter_pdfview**: Display PDF files.
    - **pdf**: Generate dynamic PDF invoices.

---

## **Contributing**

If you want to contribute to this project, please follow these steps:

1. Fork the repository.
2. Create a new branch (`git checkout -b feature-branch`).
3. Commit your changes (`git commit -am 'Add new feature'`).
4. Push to the branch (`git push origin feature-branch`).
5. Create a new pull request.

---
