import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import Login from './pages/Login.jsx';
import Registro from './pages/Registro.jsx';
import Confirmacion from './pages/Confirmacion.jsx';

const App = () => (
    <BrowserRouter>
        <Routes>
            <Route path="/" element={<Navigate to="/login" replace />} />
            <Route path="/login" element={<Login />} />
            <Route path="/registro" element={<Registro />} />
            <Route path="/confirmacion" element={<Confirmacion />} />
        </Routes>
    </BrowserRouter>
);

export default App;
