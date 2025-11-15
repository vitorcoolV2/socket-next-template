# ACME Setup

The output of the `curl` command confirms that the **ACME directory endpoint** is available and functional. This indicates that the internal ACME protocol is **enabled** on your Step CA server.

---

### **Key Observations**

1. **ACME Directory Endpoint**
   The response from the `curl` command includes the following endpoints:

   ```json
   {
     "newNonce": "https://step-ca:8443/acme/acme/new-nonce",
     "newAccount": "https://step-ca:8443/acme/acme/new-account",
     "newOrder": "https://step-ca:8443/acme/acme/new-order",
     "revokeCert": "https://step-ca:8443/acme/acme/revoke-cert",
     "keyChange": "https://step-ca:8443/acme/acme/key-change"
   }
   ```

   - These are standard ACME protocol endpoints, which allow clients to interact with the CA for tasks like creating accounts, ordering certificates, and revoking certificates.
   - The presence of these endpoints confirms that the ACME provisioner is active and ready to handle requests.

2. **Insecure Flag (`--insecure`)**
   - The `--insecure` flag in the `curl` command disables SSL certificate validation. This is useful for testing but should not be used in production.
   - If you want to avoid using `--insecure`, ensure the root CA certificate (`root_ca.crt`) is trusted by your system or explicitly specify it with the `--cacert` option:
     ```bash
     curl https://step-ca:8443/acme/acme/directory --cacert /path/to/root_ca.crt
     ```

---

### **Conclusion**

The ACME protocol is **enabled** on your Step CA server, as evidenced by the availability of the ACME directory and its endpoints. You can now use ACME clients (e.g., `certbot`, `step`, or custom scripts) to automate certificate issuance.

If you encounter any issues while issuing certificates or interacting with the ACME endpoints, feel free to share the details for further assistance!
