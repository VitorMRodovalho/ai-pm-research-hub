#!/usr/bin/env python3
"""
Extract digital signature signer information from gov.br signed PDFs.

Reads all *_assinado*.pdf files in a directory, extracts PKCS7/CMS embedded
signatures, and outputs a JSON with signer names, dates, and certificate hashes.

Usage:
  python3 scripts/extract-govbr-signers.py "/path/to/pdfs"

Output: scripts/docusign-signers-extracted.json
"""

import sys
import os
import json
import hashlib
from datetime import datetime
from pathlib import Path

from pypdf import PdfReader
from asn1crypto import cms, x509 as asn1_x509

def extract_signatures_from_pdf(pdf_path: str) -> list[dict]:
    """Extract all digital signatures from a PDF file."""
    results = []
    try:
        reader = PdfReader(pdf_path)
    except Exception as e:
        return [{"error": f"Cannot read PDF: {e}"}]

    # Look for signature fields in the AcroForm
    if "/AcroForm" not in reader.trailer.get("/Root", {}):
        # Try alternate path
        try:
            fields = reader.get_fields()
        except:
            fields = None
    else:
        try:
            fields = reader.get_fields()
        except:
            fields = None

    if not fields:
        return [{"error": "No form fields found"}]

    for field_name, field_obj in fields.items():
        ft = field_obj.get("/FT")
        if ft != "/Sig":
            continue

        sig_value = field_obj.get("/V")
        if not sig_value:
            continue

        # Extract raw PKCS7 bytes from /Contents
        contents = sig_value.get("/Contents")
        if not contents:
            continue

        if isinstance(contents, bytes):
            pkcs7_bytes = contents
        else:
            pkcs7_bytes = bytes(contents)

        # Parse the CMS/PKCS7 structure
        try:
            content_info = cms.ContentInfo.load(pkcs7_bytes)
            signed_data = content_info["content"]

            # Extract signer info
            for signer_info in signed_data["signer_infos"]:
                signer_result = {
                    "field_name": field_name,
                }

                # Get signing time from authenticated attributes
                if signer_info["signed_attrs"]:
                    for attr in signer_info["signed_attrs"]:
                        if attr["type"].dotted == "1.2.840.113549.1.9.5":  # signing-time
                            signing_time = attr["values"][0].native
                            if isinstance(signing_time, datetime):
                                signer_result["signed_at"] = signing_time.isoformat()

                # Get certificate for this signer
                sid = signer_info["sid"]
                for cert_data in signed_data["certificates"]:
                    cert = cert_data.chosen
                    tbs = cert["tbs_certificate"]

                    # Match by issuer + serial
                    if sid.name == "issuer_and_serial_number":
                        if (tbs["serial_number"].native == sid.chosen["serial_number"].native):
                            subject = tbs["subject"]
                            signer_result["signer_cn"] = subject.human_friendly

                            # Extract individual fields
                            for rdn in subject.chosen:
                                for attr in rdn:
                                    oid = attr["type"].dotted
                                    val = attr["value"].native
                                    if oid == "2.5.4.3":  # CN
                                        signer_result["common_name"] = val
                                    elif oid == "2.5.4.6":  # C
                                        signer_result["country"] = val
                                    elif oid == "2.5.4.10":  # O
                                        signer_result["organization"] = val
                                    elif oid == "2.5.4.11":  # OU
                                        signer_result.setdefault("org_units", []).append(val)

                            # Certificate validity
                            validity = tbs["validity"]
                            signer_result["cert_not_before"] = validity["not_before"].native.isoformat()
                            signer_result["cert_not_after"] = validity["not_after"].native.isoformat()

                            # Certificate hash for audit trail
                            cert_bytes = cert.dump()
                            signer_result["cert_sha256"] = hashlib.sha256(cert_bytes).hexdigest()[:16]

                            # Issuer
                            issuer = tbs["issuer"]
                            signer_result["issuer_cn"] = issuer.human_friendly
                            break

                results.append(signer_result)

        except Exception as e:
            results.append({"error": f"PKCS7 parse error: {e}", "field_name": field_name})

    return results


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 extract-govbr-signers.py /path/to/pdfs")
        sys.exit(1)

    pdf_dir = Path(sys.argv[1])
    if not pdf_dir.is_dir():
        print(f"Error: {pdf_dir} is not a directory")
        sys.exit(1)

    pdf_files = sorted(pdf_dir.glob("*_assinado*.pdf"))
    print(f"Found {len(pdf_files)} signed PDFs in {pdf_dir}")

    all_results = []
    errors = []

    for pdf_path in pdf_files:
        filename = pdf_path.name
        volunteer_name = filename.replace("_assinado_assinado.pdf", "").replace("_assinado.pdf", "").replace("_", " ")

        sigs = extract_signatures_from_pdf(str(pdf_path))

        entry = {
            "pdf_filename": filename,
            "volunteer_name_from_filename": volunteer_name,
            "signatures": [],
        }

        for sig in sigs:
            if "error" in sig:
                entry.setdefault("errors", []).append(sig["error"])
            else:
                entry["signatures"].append(sig)

        # Categorize signers (volunteer vs institutional)
        if len(entry["signatures"]) >= 2:
            # Multiple signers — try to identify institutional vs volunteer
            for sig in entry["signatures"]:
                cn = sig.get("common_name", "")
                # Heuristic: if org contains "gov" or signer name doesn't match volunteer, it's institutional
                if any(x in cn.lower() for x in volunteer_name.lower().split()[:2]):
                    sig["role"] = "volunteer"
                else:
                    sig["role"] = "institutional"
        elif len(entry["signatures"]) == 1:
            entry["signatures"][0]["role"] = "single_signer"

        if entry.get("errors"):
            errors.append(entry)

        all_results.append(entry)

    # Output
    output = {
        "extracted_at": datetime.now().isoformat(),
        "source_directory": str(pdf_dir),
        "total_pdfs": len(pdf_files),
        "total_with_signatures": sum(1 for r in all_results if r["signatures"]),
        "total_errors": len(errors),
        "results": all_results,
    }

    output_path = Path(__file__).parent / "docusign-signers-extracted.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False, default=str)

    print(f"\nResults written to {output_path}")
    print(f"  PDFs processed: {len(pdf_files)}")
    print(f"  With signatures: {output['total_with_signatures']}")
    print(f"  Errors: {output['total_errors']}")

    # Quick summary
    print("\n--- SIGNER SUMMARY ---")
    for r in all_results:
        vol = r["volunteer_name_from_filename"]
        sigs = r["signatures"]
        errs = r.get("errors", [])
        if errs:
            print(f"  ERROR {vol}: {errs[0][:60]}")
        elif not sigs:
            print(f"  NO SIGS {vol}")
        else:
            names = [s.get("common_name", "?") for s in sigs]
            roles = [s.get("role", "?") for s in sigs]
            print(f"  {vol}: {len(sigs)} sig(s) → {', '.join(f'{n} [{r}]' for n, r in zip(names, roles))}")


if __name__ == "__main__":
    main()
