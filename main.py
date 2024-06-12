import tkinter as tk
from tkinter import messagebox
import r1
import r2

def ejecutar_r1():
    r1.opcion1()

def ejecutar_r2():
    r2.opcion2()

def salir():
    root.destroy()

root = tk.Tk()
root.title("Menú Principal")
root.geometry("300x200")

label = tk.Label(root, text="Seleccione una opción", font=("Arial", 14))
label.pack(pady=20)

boton_r1 = tk.Button(root, text="Opción 1", command=ejecutar_r1)
boton_r1.pack(pady=5)

boton_r2 = tk.Button(root, text="Opción 221", command=ejecutar_r2)
boton_r2.pack(pady=5)

boton_salir = tk.Button(root, text="Salir", command=salir)
boton_salir.pack(pady=20)

root.mainloop()
