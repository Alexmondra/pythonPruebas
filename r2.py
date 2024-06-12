import tkinter as tk
from tkinter import messagebox

def sumar_numeros(entry1, entry2, label_resultado):
    try:
        num1 = float(entry1.get())
        num2 = float(entry2.get())
        resultado = num1 + num2
        label_resultado.config(text=f"Resultado: {resultado}")
    except ValueError:
        messagebox.showerror("Error", "Por favor, ingrese números válidos")

def opcion2():
    ventana = tk.Toplevel()
    ventana.title("Opción 2")
    ventana.geometry("300x250")

    label = tk.Label(ventana, text="Ingrese dos números para sumar:", font=("Arial", 12))
    label.pack(pady=10)

    entry1 = tk.Entry(ventana)
    entry1.pack(pady=5)

    entry2 = tk.Entry(ventana)
    entry2.pack(pady=5)

    boton_sumar = tk.Button(ventana, text="Sumar", command=lambda: sumar_numeros(entry1, entry2, label_resultado))
    boton_sumar.pack(pady=10)

    label_resultado = tk.Label(ventana, text="", font=("Arial", 12))
    label_resultado.pack(pady=10)

    boton_cerrar = tk.Button(ventana, text="Cerrar", command=ventana.destroy)
    boton_cerrar.pack(pady=10)

    ventana.mainloop()
